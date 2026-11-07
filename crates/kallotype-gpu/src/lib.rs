//! A wgpu backend that must agree with [`kallotype_core`].
//!
//! The point of this crate is not speed yet. It is that a second implementation
//! of the model exists and is held to a number: [`Gpu::render`] and
//! [`kallotype_core::render_pixels`] are compared on the same pixels, and the
//! difference is asserted against [`TOLERANCE`]. A GPU port that "looks right"
//! is how a film simulation acquires two different films.
//!
//! ## What it covers
//!
//! The **scalar path only**. The spectral stages integrate over wavelength, so a
//! backend that wants them has to port the integration rather than a handful of
//! solved constants; that is a later phase, and [`Gpu::render`] returns
//! [`GpuError::NotScalar`] rather than silently rendering something else.
//!
//! ## Where the tolerance comes from
//!
//! The CPU runs in f64 and the shader in f32, so the difference is rounding, and
//! the interesting part is how the model amplifies it. Two places do: the
//! characteristic curve's slope (about `gamma` densities per decade) and the
//! print's logistic, which is steepest near the anchor. Both are *stable* —
//! they multiply an error rather than growing one — so the difference stays
//! bounded. Measured across a 2 048-pixel grid that spans the toe and the
//! shoulder, the worst per-channel difference is `2.2e-7` in linear light, and
//! [`TOLERANCE`] is set nearly three orders of magnitude above it.
//!
//! ## No adapter, no test
//!
//! CI runners have no GPU and some have no software rasteriser either. The test
//! skips when no adapter can be opened, and says so, because a GPU test that
//! fails on a machine without a GPU teaches people to ignore it.

use kallotype_core::{PreparedRender, ScalarModel};

/// The largest per-channel difference the two backends are allowed, in linear
/// light.
///
/// Measured on this model the worst difference is `2.2e-7`; the bound is set
/// nearly three orders of magnitude above it so it catches a wrong
/// implementation rather than a rounding mode.
pub const TOLERANCE: f64 = 1.0e-4;

/// Why the GPU backend could not render.
#[derive(Debug)]
pub enum GpuError {
    /// No adapter, or the device could not be created.
    NoAdapter(String),
    /// The render uses a stage this backend does not implement.
    NotScalar,
    /// The pixel count does not match the buffer size used.
    Empty,
}

impl std::fmt::Display for GpuError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NoAdapter(message) => write!(formatter, "no GPU adapter: {message}"),
            Self::NotScalar => write!(
                formatter,
                "this backend implements the scalar path only; turn off --spectral, \
                 --spectral-print, --spectral-scan and --lut"
            ),
            Self::Empty => write!(formatter, "no pixels to render"),
        }
    }
}

impl std::error::Error for GpuError {}

/// A device and a compute pipeline, reused across renders.
pub struct Gpu {
    device: wgpu::Device,
    queue: wgpu::Queue,
    pipeline: wgpu::ComputePipeline,
    binder: wgpu::BindGroupLayout,
    adapter: wgpu::AdapterInfo,
}

impl std::fmt::Debug for Gpu {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.debug_struct("Gpu").finish_non_exhaustive()
    }
}

impl Gpu {
    /// Which device is doing the work, for the render report.
    ///
    /// A user who is told "GPU" and sees no speedup deserves to know that it was
    /// a software rasteriser or a twelve-year-old integrated chip.
    #[must_use]
    pub fn describe(&self) -> String {
        format!("{} ({:?})", self.adapter.name, self.adapter.backend)
    }

    /// Open the default adapter and build the pipeline.
    ///
    /// # Errors
    ///
    /// [`GpuError::NoAdapter`] when there is no adapter to open, which is the
    /// normal case on a CI runner.
    pub fn new() -> Result<Self, GpuError> {
        // `default()` would compile every backend and still honour nothing: the
        // environment override lives in `from_env_or_default`, so a machine with
        // a broken driver — or a laptop with two GPUs and the wrong one first —
        // can be told `WGPU_BACKEND=vulkan` without a rebuild.
        let descriptor = wgpu::InstanceDescriptor::from_env_or_default();
        let instance = wgpu::Instance::new(&descriptor);
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            force_fallback_adapter: false,
            compatible_surface: None,
        }))
        .map_err(|error| GpuError::NoAdapter(error.to_string()))?;

        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("kallotype"),
            required_features: wgpu::Features::empty(),
            required_limits: wgpu::Limits::downlevel_defaults(),
            ..Default::default()
        }))
        .map_err(|error| GpuError::NoAdapter(error.to_string()))?;

        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("scalar"),
            source: wgpu::ShaderSource::Wgsl(include_str!("../shaders/scalar.wgsl").into()),
        });

        let binder = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("scalar"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 2,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
            ],
        });

        let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("scalar"),
            bind_group_layouts: &[&binder],
            push_constant_ranges: &[],
        });

        let pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("scalar"),
            layout: Some(&layout),
            module: &shader,
            entry_point: Some("main"),
            compilation_options: Default::default(),
            cache: None,
        });

        Ok(Self {
            device,
            queue,
            pipeline,
            binder,
            adapter: adapter.get_info(),
        })
    }

    /// Render pixels through the scalar model.
    ///
    /// # Errors
    ///
    /// [`GpuError::NotScalar`] when the prepared render uses any spectral stage,
    /// and [`GpuError::Empty`] for an empty image.
    pub fn render(
        &self,
        pixels: &[[f64; 3]],
        prepared: &PreparedRender,
    ) -> Result<Vec<[f64; 3]>, GpuError> {
        let model = prepared.scalar_model().ok_or(GpuError::NotScalar)?;
        self.render_model(pixels, &model)
    }

    /// The same, from the flattened numbers.
    ///
    /// # Errors
    ///
    /// [`GpuError::Empty`] for an empty image.
    pub fn render_model(
        &self,
        pixels: &[[f64; 3]],
        model: &ScalarModel,
    ) -> Result<Vec<[f64; 3]>, GpuError> {
        if pixels.is_empty() {
            return Err(GpuError::Empty);
        }

        let bytes = (pixels.len() * 16) as u64;
        let uniform = self.uniform(model);
        let uniform_buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("params"),
            size: uniform.len() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        self.queue.write_buffer(&uniform_buffer, 0, &uniform);

        let mut input_bytes = Vec::with_capacity(bytes as usize);
        for pixel in pixels {
            for channel in pixel {
                input_bytes.extend_from_slice(&(*channel as f32).to_le_bytes());
            }
            input_bytes.extend_from_slice(&1.0_f32.to_le_bytes());
        }
        let input = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("input"),
            size: bytes,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        self.queue.write_buffer(&input, 0, &input_bytes);

        let output = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("output"),
            size: bytes,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        let staging = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("staging"),
            size: bytes,
            usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("scalar"),
            layout: &self.binder,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: uniform_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: input.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: output.as_entire_binding(),
                },
            ],
        });

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("scalar"),
            });
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("scalar"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, &bind_group, &[]);
            let groups = pixels.len().div_ceil(64) as u32;
            pass.dispatch_workgroups(groups, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&output, 0, &staging, 0, bytes);
        self.queue.submit([encoder.finish()]);

        let slice = staging.slice(..);
        let (sender, receiver) = std::sync::mpsc::channel();
        slice.map_async(wgpu::MapMode::Read, move |result| {
            let _ = sender.send(result);
        });
        self.device
            .poll(wgpu::PollType::Wait)
            .map_err(|error| GpuError::NoAdapter(format!("waiting for the readback: {error}")))?;
        receiver
            .recv()
            .map_err(|error| GpuError::NoAdapter(error.to_string()))?
            .map_err(|error| GpuError::NoAdapter(error.to_string()))?;

        let mapped = slice.get_mapped_range();
        let mut out = Vec::with_capacity(pixels.len());
        for chunk in mapped.chunks_exact(16) {
            let mut pixel = [0.0; 3];
            for (channel, slot) in pixel.iter_mut().enumerate() {
                let start = channel * 4;
                *slot = f32::from_le_bytes([
                    chunk[start],
                    chunk[start + 1],
                    chunk[start + 2],
                    chunk[start + 3],
                ]) as f64;
            }
            out.push(pixel);
        }
        drop(mapped);
        staging.unmap();
        Ok(out)
    }

    /// The uniform buffer for a model, in the layout `scalar.wgsl` expects.
    fn uniform(&self, model: &ScalarModel) -> Vec<u8> {
        let mut floats: Vec<f32> = Vec::with_capacity(20);
        for curve in &model.curve {
            floats.extend(curve.iter().map(|&value| value as f32));
        }
        // (paper d_min, paper span, enlarger slope, exposure shift)
        floats.push(model.paper[0] as f32);
        floats.push(model.paper[1] as f32);
        floats.push(model.print[0] as f32);
        floats.push(model.exposure_shift as f32);
        // The three anchors, padded to a vec4.
        floats.extend(model.print[1..4].iter().map(|&value| value as f32));
        floats.push(0.0);
        floats
            .iter()
            .flat_map(|value| value.to_le_bytes())
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use kallotype_core::{RenderParams, render_pixels};

    /// A spread of linear-light colours, dense enough that some of them land on
    /// the steep parts of both curves. A grid of mid-greys would pass whatever
    /// the shader did.
    fn pixels() -> Vec<[f64; 3]> {
        let mut out = Vec::new();
        for i in 0..32 {
            for j in 0..32 {
                let a = (i as f64 + 0.5) / 32.0;
                let b = (j as f64 + 0.5) / 32.0;
                out.push([a, b, 1.0 - 0.5 * (a + b)]);
                out.push([a * a * 4.0, b * 0.05, (a * b).sqrt()]);
            }
        }
        out.push([0.0; 3]);
        out.push([1.0; 3]);
        out.push([0.0001, 0.5, 4.0]);
        out
    }

    /// The whole point of the crate: two implementations, one number between
    /// them.
    #[test]
    fn the_gpu_matches_the_cpu_within_the_stated_tolerance() {
        let gpu = match Gpu::new() {
            Ok(gpu) => gpu,
            Err(error) => {
                eprintln!("skipping the GPU comparison: {error}");
                return;
            }
        };
        let prepared = RenderParams::default().prepare();
        let input = pixels();

        let mut cpu = input.clone();
        render_pixels(&mut cpu, &prepared);
        let gpu_out = gpu
            .render(&input, &prepared)
            .expect("the scalar path renders");

        assert_eq!(cpu.len(), gpu_out.len());
        let mut worst = 0.0_f64;
        let mut where_worst = [0.0; 3];
        for (index, (a, b)) in cpu.iter().zip(&gpu_out).enumerate() {
            for channel in 0..3 {
                let difference = (a[channel] - b[channel]).abs();
                if difference > worst {
                    worst = difference;
                    where_worst = input[index];
                }
            }
        }
        assert!(
            worst < TOLERANCE,
            "worst difference {worst:.2e} at input {where_worst:?}, tolerance {TOLERANCE:.0e}"
        );
    }

    /// A spectral render cannot be pushed through a backend that does not
    /// integrate, and it must say so instead of rendering the scalar path.
    #[test]
    fn a_spectral_render_is_refused() {
        let gpu = match Gpu::new() {
            Ok(gpu) => gpu,
            Err(_) => return,
        };
        let prepared = RenderParams {
            spectral: true,
            ..RenderParams::default()
        }
        .prepare();
        assert!(matches!(
            gpu.render(&[[0.18; 3]], &prepared),
            Err(GpuError::NotScalar)
        ));
    }
}

#[cfg(test)]
mod timing {
    use super::*;
    use kallotype_core::RenderParams;

    /// Not an assertion, a measurement: how fast the two backends actually are,
    /// transfer included, on a frame big enough to matter.
    ///
    /// Ignored by default because it takes seconds and because a GPU benchmark on
    /// a CI runner measures the absence of a GPU.
    #[test]
    #[ignore = "timing, not correctness; run with --ignored --nocapture"]
    fn how_fast_is_it_actually() {
        let gpu = Gpu::new().expect("a GPU adapter");
        let prepared = RenderParams::default().prepare();
        let mut pixels = Vec::with_capacity(1920 * 1080);
        for y in 0..1080u32 {
            for x in 0..1920u32 {
                let a = x as f64 / 1920.0;
                let b = y as f64 / 1080.0;
                pixels.push([a, b, (a * b).sqrt()]);
            }
        }

        let mut cpu = pixels.clone();
        let start = std::time::Instant::now();
        kallotype_core::render_pixels(&mut cpu, &prepared);
        let cpu_time = start.elapsed();

        let start = std::time::Instant::now();
        let gpu_out = gpu.render(&pixels, &prepared).expect("renders");
        let gpu_time = start.elapsed();

        println!(
            "{} px: cpu {:.1} ms, gpu {:.1} ms (upload + dispatch + readback), ratio {:.2}x",
            pixels.len(),
            cpu_time.as_secs_f64() * 1e3,
            gpu_time.as_secs_f64() * 1e3,
            cpu_time.as_secs_f64() / gpu_time.as_secs_f64()
        );
        assert_eq!(gpu_out.len(), cpu.len());
    }
}
