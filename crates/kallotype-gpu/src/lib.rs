//! A wgpu backend that must agree with [`kallotype_core`].
//!
//! The point of this crate is not speed. It is that a second implementation of
//! the model exists and is held to a number: [`Gpu::render_finished`] and
//! [`kallotype_core::render_pixels_finished`] are compared on the same pixels,
//! and the difference is asserted against [`TOLERANCE`]. A GPU port that "looks
//! right" is how a film simulation acquires two different films.
//!
//! ## One model, not two
//!
//! The scalar path is the spectral one with its three spectral stages turned off,
//! exactly as it is on the CPU, and the shader branches on the same three flags.
//! That is worth saying because the alternative — a compact scalar shader beside
//! the spectral one — was what this crate used to have, and two transcriptions of
//! one model is two things to keep in step. There is now one.
//!
//! Nothing is re-derived on the device. The prepared render hands over what the
//! CPU solved, or — where the model integrates over wavelength and there is no
//! answer to hand over — the tables it integrates on, plus the three 3×3 systems
//! already inverted so the shader multiplies where the CPU would solve.
//!
//! ## Two ways to run it
//!
//! A render with grain and no spatial effect is one dispatch: the whole model,
//! one invocation per pixel. The emulsion's own blur, halation and the DIR
//! couplers move light between pixels, which needs the frame in a buffer and a
//! separable convolution, so they run as a chain of passes — exposure, the
//! film's blur, halation, development, inhibitors, print — with the ones that
//! are off skipped. The chain is tested against the single dispatch with no
//! effects, because two ways to run a model is two ways to disagree.
//!
//! Every spatial effect is three or four kernels wide and each layer has its
//! own width, so the kernels ride in one table and a lane of the uniform says
//! where each one starts.
//!
//! Grain is in both, and it is the sharpest constraint on the transcription: its
//! draw is SplitMix64, WGSL has no 64-bit integers, so `grain.wgsl` runs the same
//! generator on pairs of `u32`. For a random draw "close enough" would be false —
//! the two backends either draw the same number or they are two films.
//!
//! ## What is not here
//!
//! A **baked exposure table** and a **dictionary prior**: a sampled cube and a
//! per-pixel non-negative least squares are their own models, and neither is
//! expressible as a constant matrix. [`Gpu::render_finished`] refuses them by
//! name rather than rendering something adjacent.
//!
//! ## Where the tolerance comes from
//!
//! The CPU runs in f64 and the shader in f32, so the difference is rounding, and
//! the interesting part is how the model amplifies it. The scalar path has two
//! amplifiers: the characteristic curve's slope (about `gamma` densities per
//! decade) and the print's logistic, which is steepest near the anchor. Both are
//! *stable* — they multiply an error rather than growing one.
//!
//! The spectral stages add four more: two `log10` per pixel, a `10^-d` per
//! wavelength, and a larger dynamic range on the way — the paper's blue layer
//! integrates to about 13 before normalisation and the observer to about 9 000.
//! Cancellation is the thing to watch, and it does not appear: the reconstruction
//! matrix is small and well scaled, and every table is non-negative.
//!
//! Measured over a 2 048-pixel grid that spans toe and shoulder, the worst
//! per-channel difference is `3.0e-7` on the scalar path, `3.6e-7` with the
//! spectral exposure, `8.2e-7` with the spectral print and `1.0e-6` with all
//! three stages, which is why one [`TOLERANCE`] covers all of them.
//!
//! Grain adds a fifth amplifier and it is the sharpest one: a draw that differs
//! at all differs by a whole standard deviation, about `5e-3` in log exposure,
//! fifty times [`TOLERANCE`]. Measured, it adds nothing — because the shader
//! draws the same number rather than a nearby one. The two spatial effects
//! convolve, so their error is a weighted average of their neighbours' and comes
//! out smaller than any single pixel's.
//!
//! ## What it costs
//!
//! Measured on 2 073 600 pixels, CPU against GPU including upload, dispatch and
//! readback:
//!
//! | render | cpu | gpu | ratio |
//! |---|---|---|---|
//! | scalar | 106 ms | 23 ms | 4.5x |
//! | all three spectral stages | 3 062 ms | 36 ms | 84x |
//! | the same, with grain | 3 174 ms | 33 ms | 97x |
//! | the same, with halation and couplers | 3 356 ms | 45 ms | 74x |
//!
//! The chain costs about ten milliseconds over the single dispatch — five passes
//! instead of one, each one reading and writing the frame. The spatial effects
//! make the CPU render 10 % slower and the GPU render 30 % slower, which is the
//! closest the two have come: a convolution is the only thing here the device is
//! not dramatically better at.
//!
//! ## No adapter, no test
//!
//! CI runners have no GPU and some have no software rasteriser either. The tests
//! skip when no adapter can be opened, and say so, because a GPU test that fails
//! on a machine without a GPU teaches people to ignore it.

#[cfg(test)]
mod replay;

use kallotype_core::model::NEUTRAL_ENTRIES;
use kallotype_core::psf::gaussian_kernel;
use kallotype_core::spectral::GRID_LEN;
use kallotype_core::{
    Couplers, EmulsionBlur, Finishing, GrainField, Halation, PreparedRender, ScalarModel,
    SpectralModel,
};

/// The largest per-channel difference the two backends are allowed, in linear
/// light.
///
/// Measured on this model the worst difference is `3.0e-7` on the scalar path
/// and `1.0e-6` on the full spectral one, with or without grain; the bound is set
/// two orders of magnitude above them so it catches a wrong implementation
/// rather than a rounding mode.
pub const TOLERANCE: f64 = 1.0e-4;

/// The widest effect kernel the GPU will apply, in taps.
///
/// The kernels are `3 sigma` either side, normalised, and they arrive on the
/// device precomputed. A kernel wider than this is a blur of several hundred
/// pixels: the CPU can run it, the chain would take minutes, and the honest answer
/// is to fall back rather than to truncate a kernel and silently blur less.
pub const MAX_KERNEL_TAPS: usize = 4_097;

/// Why the GPU backend could not render.
#[derive(Debug)]
pub enum GpuError {
    /// No adapter, or the device could not be created.
    NoAdapter(String),
    /// The render uses a stage this backend does not implement, named.
    Unsupported(&'static str),
    /// An effect kernel is wider than [`MAX_KERNEL_TAPS`].
    KernelTooWide(usize),
    /// The frame shape does not describe the pixels handed in.
    Shape {
        /// Declared width.
        width: usize,
        /// Declared height.
        height: usize,
        /// Pixels actually handed in.
        pixels: usize,
    },
    /// The pixel count does not match the buffer size used.
    Empty,
}

impl std::fmt::Display for GpuError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NoAdapter(message) => write!(formatter, "no GPU adapter: {message}"),
            Self::Unsupported(stage) => {
                write!(formatter, "the gpu backend does not implement {stage}")
            }
            Self::KernelTooWide(taps) => write!(
                formatter,
                "an effect kernel of {taps} taps is wider than the {MAX_KERNEL_TAPS} the gpu \
                 backend applies"
            ),
            Self::Shape {
                width,
                height,
                pixels,
            } => write!(
                formatter,
                "a {width}x{height} frame is {} pixels, not {pixels}",
                width * height
            ),
            Self::Empty => write!(formatter, "no pixels to render"),
        }
    }
}

impl std::error::Error for GpuError {}

/// A device and the eight compute pipelines, reused across renders.
pub struct Gpu {
    device: wgpu::Device,
    queue: wgpu::Queue,
    binder: wgpu::BindGroupLayout,
    passes: Passes,
    adapter: wgpu::AdapterInfo,
}

/// The entry points, one per pass.
struct Passes {
    simple: wgpu::ComputePipeline,
    expose: wgpu::ComputePipeline,
    positive: wgpu::ComputePipeline,
    blur_horizontal: wgpu::ComputePipeline,
    blur_vertical: wgpu::ComputePipeline,
    halation_horizontal: wgpu::ComputePipeline,
    halation_vertical: wgpu::ComputePipeline,
    develop: wgpu::ComputePipeline,
    couplers_horizontal: wgpu::ComputePipeline,
    couplers_vertical: wgpu::ComputePipeline,
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

    /// Open the default adapter and build every pipeline.
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

        // `downlevel_defaults` guarantees four storage buffers; the chain needs
        // seven — the model's tables, the kernels, and three working planes —
        // which is what every current backend offers and what WebGPU itself
        // requires. Asking for it explicitly means a device that cannot fails
        // here, where the caller can fall back, instead of at the bind group.
        // The defaults are tuned for a texture-sized buffer: 256 MiB, and 128
        // MiB of it bindable. A full-frame 16-bit scan is 500 MiB of working
        // buffer per plane, so the limits are taken from the adapter rather
        // than from the defaults — which is what makes a camera-sized frame
        // render instead of panicking inside wgpu.
        let supported = adapter.limits();
        let mut limits = wgpu::Limits::downlevel_defaults().using_resolution(supported.clone());
        limits.max_storage_buffers_per_shader_stage = 8;
        limits.max_buffer_size = supported.max_buffer_size;
        limits.max_storage_buffer_binding_size = supported.max_storage_buffer_binding_size;

        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("kallotype"),
            required_features: wgpu::Features::empty(),
            required_limits: limits,
            ..Default::default()
        }))
        .map_err(|error| GpuError::NoAdapter(error.to_string()))?;

        let binder = bind_group_layout(&device);
        let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("kallotype"),
            bind_group_layouts: &[&binder],
            push_constant_ranges: &[],
        });

        // Three modules, not eight: everything between the exposure and the print
        // is model independent, so the chain compiles once and the two ends carry
        // the model.
        let simple_source = format!("{PARAMS}\n{GRAIN}\n{COMMON}\n{MODEL}\n{SIMPLE}");
        let chain_source = format!("{PARAMS}\n{GRAIN}\n{COMMON}\n{CHAIN}");
        let end_source = format!("{PARAMS}\n{GRAIN}\n{COMMON}\n{MODEL}\n{CHAIN_MODEL}");

        let module = |label: &'static str, source: &str| {
            device.create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some(label),
                source: wgpu::ShaderSource::Wgsl(source.into()),
            })
        };
        let simple_module = module("simple", &simple_source);
        let chain_module = module("chain", &chain_source);
        let end_module = module("ends", &end_source);

        let pipeline = |label: &'static str,
                        module: &wgpu::ShaderModule,
                        entry: &str|
         -> wgpu::ComputePipeline {
            device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some(label),
                layout: Some(&layout),
                module,
                entry_point: Some(entry),
                compilation_options: Default::default(),
                cache: None,
            })
        };

        let passes = Passes {
            simple: pipeline("simple", &simple_module, "main"),
            expose: pipeline("expose", &end_module, "expose"),
            positive: pipeline("positive", &end_module, "positive"),
            blur_horizontal: pipeline("blur_horizontal", &chain_module, "blur_horizontal"),
            blur_vertical: pipeline("blur_vertical", &chain_module, "blur_vertical"),
            halation_horizontal: pipeline(
                "halation_horizontal",
                &chain_module,
                "halation_horizontal",
            ),
            halation_vertical: pipeline("halation_vertical", &chain_module, "halation_vertical"),
            develop: pipeline("develop", &chain_module, "develop_pass"),
            couplers_horizontal: pipeline(
                "couplers_horizontal",
                &chain_module,
                "couplers_horizontal",
            ),
            couplers_vertical: pipeline("couplers_vertical", &chain_module, "couplers_vertical"),
        };

        Ok(Self {
            device,
            queue,
            binder,
            passes,
            adapter: adapter.get_info(),
        })
    }

    /// Render pixels through whichever model the render prepared.
    ///
    /// # Errors
    ///
    /// [`GpuError::Unsupported`] when the render uses a stage this backend does
    /// not implement, and [`GpuError::Empty`] for an empty image.
    pub fn render(
        &self,
        pixels: &[[f64; 3]],
        prepared: &PreparedRender,
    ) -> Result<Vec<[f64; 3]>, GpuError> {
        self.render_finished(
            pixels,
            prepared,
            pixels.len().max(1),
            1,
            &Finishing::default(),
        )
    }

    /// Render an image with the finishing effects the CPU model has.
    ///
    /// `width` and `height` are the frame's shape, which the spatial effects need
    /// and a flat pixel buffer cannot carry.
    ///
    /// # Errors
    ///
    /// [`GpuError::Unsupported`] when the render needs a model this backend does
    /// not implement, [`GpuError::KernelTooWide`] when an effect kernel exceeds
    /// [`MAX_KERNEL_TAPS`], and [`GpuError::Empty`] for an empty image.
    pub fn render_finished(
        &self,
        pixels: &[[f64; 3]],
        prepared: &PreparedRender,
        width: usize,
        height: usize,
        finishing: &Finishing,
    ) -> Result<Vec<[f64; 3]>, GpuError> {
        self.run(pixels, prepared, width, height, finishing, false)
    }

    /// The render itself. `force_chain` is a test hook: it runs the chain even
    /// when no effect needs it, which is the only way to compare the two shapes
    /// of the same model against each other.
    fn run(
        &self,
        pixels: &[[f64; 3]],
        prepared: &PreparedRender,
        width: usize,
        height: usize,
        finishing: &Finishing,
        force_chain: bool,
    ) -> Result<Vec<[f64; 3]>, GpuError> {
        if pixels.is_empty() {
            return Err(GpuError::Empty);
        }
        if width.max(1) * height.max(1) != pixels.len() {
            return Err(GpuError::Shape {
                width,
                height,
                pixels: pixels.len(),
            });
        }
        let (width, height) = (width.max(1) as u32, height.max(1) as u32);

        let (scalar, spectral) = match (prepared.scalar_model(), prepared.spectral_model()) {
            (Some(scalar), _) => (scalar, None),
            (None, Some(spectral)) => (spectral.scalar, Some(spectral)),
            (None, None) => {
                return Err(GpuError::Unsupported(
                    "a baked exposure table or a dictionary prior",
                ));
            }
        };

        // An effect that is all zeros is a no-op, and running the chain for it
        // would cost five dispatches to change nothing.
        let halation = finishing
            .halation
            .filter(|halation| !halation.is_noop())
            .copied();
        let couplers = finishing
            .couplers
            .filter(|couplers| !couplers.is_noop())
            .copied();
        let emulsion = finishing
            .emulsion
            .filter(|emulsion| !emulsion.is_noop())
            .copied();
        let kernels = EffectKernels::build(halation, couplers, emulsion)?;

        let uniform = uniform(
            &scalar,
            spectral.as_ref(),
            finishing.grain,
            width,
            height,
            halation,
            couplers,
            &kernels,
        );
        let tables = spectral
            .as_ref()
            .map_or_else(|| vec![0.0_f32; TABLE_FLOATS], spectral_tables);

        let count = pixels.len();
        let bytes = (count * 16) as u64;

        let uniform_buffer = self.buffer(
            "params",
            uniform.len() as u64,
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        );
        self.queue.write_buffer(&uniform_buffer, 0, &uniform);

        let mut source_bytes = Vec::with_capacity(bytes as usize);
        for pixel in pixels {
            for channel in pixel {
                source_bytes.extend_from_slice(&(*channel as f32).to_le_bytes());
            }
            source_bytes.extend_from_slice(&1.0_f32.to_le_bytes());
        }
        let source = self.buffer(
            "source",
            bytes,
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        );
        self.queue.write_buffer(&source, 0, &source_bytes);

        let output = self.buffer(
            "output",
            bytes,
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        );
        let staging = self.buffer(
            "staging",
            bytes,
            wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
        );

        let table_bytes: Vec<u8> = tables
            .iter()
            .flat_map(|value| value.to_le_bytes())
            .collect();
        let table_buffer = self.buffer(
            "tables",
            table_bytes.len() as u64,
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        );
        self.queue.write_buffer(&table_buffer, 0, &table_bytes);

        let kernel_bytes: Vec<u8> = kernels
            .floats
            .iter()
            .flat_map(|value| value.to_le_bytes())
            .collect();
        let kernel_buffer = self.buffer(
            "kernels",
            kernel_bytes.len().max(16) as u64,
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        );
        if !kernel_bytes.is_empty() {
            self.queue.write_buffer(&kernel_buffer, 0, &kernel_bytes);
        }

        // The chain's working buffers. The single dispatch does not touch them,
        // but the bind group has to name something for every binding.
        let chain = force_chain || halation.is_some() || couplers.is_some() || emulsion.is_some();
        let work = |label| {
            self.buffer(
                label,
                if chain { bytes } else { 16 },
                wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            )
        };
        let exposure = work("exposure");
        let density = work("density");
        let scratch = work("scratch");

        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("kallotype"),
            layout: &self.binder,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: uniform_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: source.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: output.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: table_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 4,
                    resource: exposure.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 5,
                    resource: density.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 6,
                    resource: scratch.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 7,
                    resource: kernel_buffer.as_entire_binding(),
                },
            ],
        });

        // One workgroup row per image row. A flat dispatch would need
        // `count / 64` workgroups in one dimension, and WebGPU caps that at
        // 65535 — a limit a 4 MP image crosses. Splitting the grid over two
        // dimensions keeps every dispatch inside it however large the frame.
        let groups_x = width.div_ceil(64);
        let groups_y = height;
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("kallotype"),
            });
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("kallotype"),
                timestamp_writes: None,
            });
            pass.set_bind_group(0, &bind_group, &[]);
            let mut dispatch = |pipeline: &wgpu::ComputePipeline| {
                pass.set_pipeline(pipeline);
                pass.dispatch_workgroups(groups_x, groups_y, 1);
            };
            if chain {
                dispatch(&self.passes.expose);
                if emulsion.is_some() {
                    dispatch(&self.passes.blur_horizontal);
                    dispatch(&self.passes.blur_vertical);
                }
                if halation.is_some() {
                    dispatch(&self.passes.halation_horizontal);
                    dispatch(&self.passes.halation_vertical);
                }
                dispatch(&self.passes.develop);
                if couplers.is_some() {
                    dispatch(&self.passes.couplers_horizontal);
                    dispatch(&self.passes.couplers_vertical);
                }
                dispatch(&self.passes.positive);
            } else {
                dispatch(&self.passes.simple);
            }
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
        let mut out = Vec::with_capacity(count);
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

    fn buffer(&self, label: &str, size: u64, usage: wgpu::BufferUsages) -> wgpu::Buffer {
        self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size,
            usage,
            mapped_at_creation: false,
        })
    }
}

/// One bind group layout for every pass, so a pass cannot read the kernel table
/// where it expected the model.
fn bind_group_layout(device: &wgpu::Device) -> wgpu::BindGroupLayout {
    let entry = |binding: u32, ty: wgpu::BufferBindingType| wgpu::BindGroupLayoutEntry {
        binding,
        visibility: wgpu::ShaderStages::COMPUTE,
        ty: wgpu::BindingType::Buffer {
            ty,
            has_dynamic_offset: false,
            min_binding_size: None,
        },
        count: None,
    };
    const READ: wgpu::BufferBindingType = wgpu::BufferBindingType::Storage { read_only: true };
    const WRITE: wgpu::BufferBindingType = wgpu::BufferBindingType::Storage { read_only: false };
    device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("kallotype"),
        entries: &[
            entry(0, wgpu::BufferBindingType::Uniform),
            entry(1, READ),
            entry(2, WRITE),
            entry(3, READ),
            entry(4, WRITE),
            entry(5, WRITE),
            entry(6, WRITE),
            entry(7, READ),
        ],
    })
}

// ---------------------------------------------------------------------------
// The kernels the chain applies.
// ---------------------------------------------------------------------------

/// Where each kernel sits in the table, and how long it is.
#[derive(Debug, Clone, Copy, Default)]
struct Kernel {
    offset: usize,
    length: usize,
}

/// The precomputed, normalised Gaussians for this render.
struct EffectKernels {
    floats: Vec<f32>,
    scatter: Kernel,
    reflection: Kernel,
    couplers: Kernel,
    /// The emulsion's blur, one kernel per layer: the three have their own
    /// sigma and a single kernel would flatten the film's blue layer into its
    /// red one.
    blur: [Kernel; 3],
}

impl EffectKernels {
    fn build(
        halation: Option<Halation>,
        couplers: Option<Couplers>,
        emulsion: Option<EmulsionBlur>,
    ) -> Result<Self, GpuError> {
        let mut floats = Vec::new();
        let mut append = |sigma_px: f64| -> Result<Kernel, GpuError> {
            if sigma_px <= 0.0 {
                // An inert component contributes nothing, and a zero-length
                // kernel is how the shader is told so.
                return Ok(Kernel::default());
            }
            let values = gaussian_kernel(sigma_px);
            if values.len() > MAX_KERNEL_TAPS {
                return Err(GpuError::KernelTooWide(values.len()));
            }
            let offset = floats.len();
            floats.extend(values.iter().map(|&value| value as f32));
            Ok(Kernel {
                offset,
                length: values.len(),
            })
        };

        let (scatter, reflection) = match halation {
            Some(halation) => (
                append(halation.scatter.sigma_um / halation.pixel_um.max(1e-9))?,
                append(halation.reflection.sigma_um / halation.pixel_um.max(1e-9))?,
            ),
            None => (Kernel::default(), Kernel::default()),
        };
        let couplers = match couplers {
            Some(couplers) => append(couplers.sigma_um / couplers.pixel_um.max(1e-9))?,
            None => Kernel::default(),
        };
        let mut blur = [Kernel::default(); 3];
        if let Some(emulsion) = emulsion {
            for (kernel, sigma) in blur.iter_mut().zip(emulsion.sigma_um) {
                *kernel = append(sigma / emulsion.pixel_um.max(1e-9))?;
            }
        }

        Ok(Self {
            floats,
            scatter,
            reflection,
            blur,
            couplers,
        })
    }
}

// ---------------------------------------------------------------------------
// The uniform, in the order `params.wgsl` declares it.
// ---------------------------------------------------------------------------

/// Append values as little-endian f32.
fn push_f32(out: &mut Vec<u8>, values: &[f32]) {
    out.extend(values.iter().flat_map(|value| value.to_le_bytes()));
}

/// Append values as little-endian u32.
fn push_u32(out: &mut Vec<u8>, values: &[u32]) {
    out.extend(values.iter().flat_map(|value| value.to_le_bytes()));
}

/// Append a lane padded out to four.
fn push_lane(out: &mut Vec<u8>, values: [f64; 3], fourth: f32) {
    push_f32(
        out,
        &[values[0] as f32, values[1] as f32, values[2] as f32, fourth],
    );
}

/// The whole uniform, for either model.
///
/// One writer for one struct: the scalar path leaves the spectral lanes at zero
/// and everything else is shared, so there is no second layout to drift.
#[allow(clippy::too_many_arguments)]
fn uniform(
    scalar: &ScalarModel,
    spectral: Option<&SpectralModel>,
    grain: Option<&GrainField>,
    width: u32,
    height: u32,
    halation: Option<Halation>,
    couplers: Option<Couplers>,
    kernels: &EffectKernels,
) -> Vec<u8> {
    let exposure = spectral.and_then(|model| model.exposure.as_ref());
    let enlarger = spectral.and_then(|model| model.enlarger.as_ref());
    let scan = spectral.and_then(|model| model.scan.as_ref());

    let mut out = Vec::with_capacity(28 * 16);
    for curve in &scalar.curve {
        push_f32(&mut out, &curve.map(|value| value as f32));
    }
    // How sharply each curve turns: the three layers, then the paper.
    push_f32(&mut out, &scalar.transition.map(|value| value as f32));
    // (paper d_min, paper d_max, paper gamma, exposure shift)
    push_f32(
        &mut out,
        &[
            scalar.paper[0] as f32,
            scalar.paper[1] as f32,
            scalar.paper[2] as f32,
            scalar.exposure_shift as f32,
        ],
    );
    // The enlarger's shift per layer, then the paper's log_e0.
    push_f32(
        &mut out,
        &[
            scalar.print_shift[0] as f32,
            scalar.print_shift[1] as f32,
            scalar.print_shift[2] as f32,
            scalar.paper[3] as f32,
        ],
    );
    // The film's minimum density in status terms, for the non-spectral print.
    push_f32(
        &mut out,
        &[
            scalar.base_density[0] as f32,
            scalar.base_density[1] as f32,
            scalar.base_density[2] as f32,
            0.0,
        ],
    );
    push_f32(
        &mut out,
        &[
            GRID_LEN as f32,
            spectral.map_or(0.0, |model| model.step_nm) as f32,
            0.0,
            0.0,
        ],
    );
    push_lane(
        &mut out,
        exposure.map_or([0.0; 3], |model| model.reference),
        0.0,
    );
    push_lane(
        &mut out,
        enlarger.map_or([0.0; 3], |model| model.reference),
        0.0,
    );
    push_f32(
        &mut out,
        &[
            enlarger.map_or(0.0, |model| model.masking[0]) as f32,
            enlarger.map_or(0.0, |model| model.masking[1]) as f32,
            enlarger.map_or(0.0, |model| model.masking[2]) as f32,
            enlarger.map_or(1.0, |model| model.masking_reference) as f32,
        ],
    );
    push_lane(
        &mut out,
        enlarger.map_or([0.0; 3], |model| model.filters),
        0.0,
    );
    push_lane(
        &mut out,
        scan.map_or([1.0; 3], |model| model.white_xyz),
        0.0,
    );
    push_lane(
        &mut out,
        scan.map_or([1.0; 3], |model| model.white_rgb),
        0.0,
    );
    push_f32(
        &mut out,
        &[
            scan.map_or(0.0, |model| model.neutral_max_density) as f32,
            // Derived from the table rather than from a second constant: the
            // neutral axis runs from density zero to its span in `len - 1` steps.
            scan.map_or(0.0, |model| (model.neutral.len() - 1) as f64) as f32,
            scan.map_or(0.0, |model| model.base_density) as f32,
            0.0,
        ],
    );
    push_f32(
        &mut out,
        &[
            flag(exposure.is_some()),
            flag(enlarger.is_some()),
            flag(scan.is_some()),
            flag(enlarger.is_some_and(|model| model.clamped)),
        ],
    );
    push_f32(
        &mut out,
        &[flag(scan.is_some_and(|model| model.clamped)), 0.0, 0.0, 0.0],
    );

    let seed = grain.map_or(0, |grain| grain.seed);
    push_u32(&mut out, &[seed as u32, (seed >> 32) as u32, width, height]);
    push_f32(
        &mut out,
        &match grain {
            Some(grain) => [
                grain.pixel_area_um2 as f32,
                grain.grains_per_um2[0] as f32,
                grain.grains_per_um2[1] as f32,
                grain.grains_per_um2[2] as f32,
            ],
            None => [0.0; 4],
        },
    );
    push_u32(
        &mut out,
        &[
            u32::from(grain.is_some()),
            u32::from(halation.is_some()),
            u32::from(couplers.is_some()),
            0,
        ],
    );

    let (scatter_strength, scatter_length) = match halation {
        Some(halation) => (halation.scatter.strength, kernels.scatter.length),
        None => ([0.0_f64; 3], 0),
    };
    let (reflection_strength, reflection_length) = match halation {
        Some(halation) => (halation.reflection.strength, kernels.reflection.length),
        None => ([0.0_f64; 3], 0),
    };
    push_lane(&mut out, scatter_strength, scatter_length as f32);
    push_lane(&mut out, reflection_strength, reflection_length as f32);
    push_f32(
        &mut out,
        &[
            kernels.scatter.offset as f32,
            kernels.reflection.offset as f32,
            0.0,
            0.0,
        ],
    );

    let inhibition = couplers.map_or([[0.0_f64; 3]; 3], |couplers| couplers.inhibition);
    let half_saturation = couplers.map_or(0.0, |couplers| couplers.half_saturation);
    push_lane(&mut out, inhibition[0], half_saturation as f32);
    push_lane(&mut out, inhibition[1], kernels.couplers.length as f32);
    push_lane(&mut out, inhibition[2], kernels.couplers.offset as f32);
    push_u32(
        &mut out,
        &[
            kernels.blur[0].offset as u32,
            kernels.blur[1].offset as u32,
            kernels.blur[2].offset as u32,
            0,
        ],
    );
    push_u32(
        &mut out,
        &[
            kernels.blur[0].length as u32,
            kernels.blur[1].length as u32,
            kernels.blur[2].length as u32,
            0,
        ],
    );
    out
}

/// The flags lane is `f32`, so a boolean has to become one.
fn flag(value: bool) -> f32 {
    if value { 1.0 } else { 0.0 }
}

// ---------------------------------------------------------------------------
// The model tables, in the order `params.wgsl` declares them.
// ---------------------------------------------------------------------------

/// Floats in `params.wgsl`'s `Tables` struct, in its declared order.
///
/// Kept as arithmetic rather than a number so that it follows [`GRID_LEN`] and
/// [`NEUTRAL_ENTRIES`]; a test asserts the writer produces exactly this many.
const TABLE_FLOATS: usize = EXPOSURE_FLOATS + PRINT_FLOATS + SCAN_FLOATS;

/// Reconstruction, basis, film layers.
const EXPOSURE_FLOATS: usize = 9 + 6 * GRID_LEN;
/// Unmixing, dye, paper layers, illuminant, mask, filter bands.
const PRINT_FLOATS: usize = 9 + 11 * GRID_LEN;
/// Unmixing, dye, observer, illuminant, matrix, neutral axis.
const SCAN_FLOATS: usize = 9 + 7 * GRID_LEN + 9 + 3 * NEUTRAL_ENTRIES;

/// The tables buffer, in the order `params.wgsl`'s `Tables` declares.
///
/// A stage that is not active still occupies its slice: the struct has a fixed
/// shape, and a buffer that grew and shrank would put the scan's dye table where
/// the print expected its own the moment someone turned a flag off.
fn spectral_tables(model: &SpectralModel) -> Vec<f32> {
    let mut floats: Vec<f32> = Vec::with_capacity(TABLE_FLOATS);
    let extend = |out: &mut Vec<f32>, values: &[f64]| {
        out.extend(values.iter().map(|&value| value as f32));
    };

    match &model.exposure {
        Some(exposure) => {
            extend(&mut floats, &exposure.reconstruct.concat());
            for row in &exposure.basis {
                extend(&mut floats, row);
            }
            for row in &exposure.film {
                extend(&mut floats, row);
            }
        }
        None => floats.resize(floats.len() + EXPOSURE_FLOATS, 0.0),
    }

    match &model.enlarger {
        Some(enlarger) => {
            extend(&mut floats, &enlarger.analytical.concat());
            for row in &enlarger.dye {
                extend(&mut floats, row);
            }
            for row in &enlarger.paper {
                extend(&mut floats, row);
            }
            extend(&mut floats, &enlarger.illuminant);
            extend(&mut floats, &enlarger.mask);
            for row in &enlarger.filter_bands {
                extend(&mut floats, row);
            }
        }
        None => floats.resize(floats.len() + PRINT_FLOATS, 0.0),
    }

    match &model.scan {
        Some(scan) => {
            extend(&mut floats, &scan.analytical.concat());
            for row in &scan.dye {
                extend(&mut floats, row);
            }
            for row in &scan.cmf {
                extend(&mut floats, row);
            }
            extend(&mut floats, &scan.illuminant);
            extend(&mut floats, &scan.matrix.concat());
            for level in &scan.neutral {
                extend(&mut floats, level);
            }
        }
        None => floats.resize(floats.len() + SCAN_FLOATS, 0.0),
    }

    debug_assert_eq!(
        floats.len(),
        TABLE_FLOATS,
        "the tables buffer must cover exactly what the shader declares"
    );
    floats
}

/// The shader sources, as files. They are concatenated in the order below.
const PARAMS: &str = include_str!("../shaders/params.wgsl");
const GRAIN: &str = include_str!("../shaders/grain.wgsl");
const COMMON: &str = include_str!("../shaders/common.wgsl");
const MODEL: &str = include_str!("../shaders/model.wgsl");
const SIMPLE: &str = include_str!("../shaders/simple.wgsl");
const CHAIN: &str = include_str!("../shaders/chain.wgsl");
const CHAIN_MODEL: &str = include_str!("../shaders/chain_model.wgsl");

#[cfg(test)]
mod tests {
    use super::*;
    use kallotype_core::{RenderParams, render_pixels, render_pixels_finished};

    const WIDTH: usize = 64;
    const HEIGHT: usize = 48;

    /// A frame with a bright patch in the middle and a dark one beside it: the
    /// blur needs something to spread and an edge to spread it across, and the
    /// grain needs a position for every pixel.
    fn frame() -> Vec<[f64; 3]> {
        let mut out = Vec::with_capacity(WIDTH * HEIGHT);
        for y in 0..HEIGHT {
            for x in 0..WIDTH {
                let a = (x as f64 + 0.5) / WIDTH as f64;
                let b = (y as f64 + 0.5) / HEIGHT as f64;
                let patch = ((x as f64 - 20.0).powi(2) + (y as f64 - 18.0).powi(2)).sqrt();
                let highlight = if patch < 5.0 { 0.85 } else { 0.0 };
                out.push([
                    a * a * 0.4 + highlight,
                    b * 0.4 + highlight,
                    (a * b).sqrt() * 0.3,
                ]);
            }
        }
        out
    }

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
        // The spectral path's reconstruction is a quadratic in wavelength, so a
        // saturated primary drives the clamp and a nearly-neutral colour drives
        // the grey balance. Both belong in the comparison.
        out.push([0.9, 0.05, 0.02]);
        out.push([0.02, 0.6, 0.02]);
        out.push([0.02, 0.05, 0.9]);
        out.push([0.18; 3]);
        out
    }

    /// The difference between the two backends, worst channel first.
    fn compare_finished(
        prepared: &PreparedRender,
        input: &[[f64; 3]],
        width: usize,
        height: usize,
        finishing: &Finishing,
    ) -> f64 {
        let gpu = match Gpu::new() {
            Ok(gpu) => gpu,
            Err(error) => {
                eprintln!("skipping the GPU comparison: {error}");
                return 0.0;
            }
        };
        let mut cpu = input.to_vec();
        render_pixels_finished(&mut cpu, prepared, width, height, finishing);
        let gpu_out = gpu
            .render_finished(input, prepared, width, height, finishing)
            .expect("the model renders");

        assert_eq!(cpu.len(), gpu_out.len());
        let mut worst = 0.0_f64;
        let mut where_worst = [0.0; 3];
        for (index, (expected, actual)) in cpu.iter().zip(&gpu_out).enumerate() {
            for channel in 0..3 {
                let difference = (expected[channel] - actual[channel]).abs();
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
        println!("worst difference {worst:.2e}");
        worst
    }

    /// A render with no spatial effect, on a frame shape that suits a `Vec`.
    fn compare(prepared: &PreparedRender) -> f64 {
        let input = pixels();
        let width = input.len();
        let mut cpu = input.clone();
        render_pixels(&mut cpu, prepared);
        let gpu = match Gpu::new() {
            Ok(gpu) => gpu,
            Err(error) => {
                eprintln!("skipping the GPU comparison: {error}");
                return 0.0;
            }
        };
        let gpu_out = gpu
            .render_finished(&input, prepared, width, 1, &Finishing::default())
            .expect("the model renders");

        let mut worst = 0.0_f64;
        for (expected, actual) in cpu.iter().zip(&gpu_out) {
            for channel in 0..3 {
                worst = worst.max((expected[channel] - actual[channel]).abs());
            }
        }
        assert!(worst < TOLERANCE, "worst difference {worst:.2e}");
        println!("worst difference {worst:.2e}");
        worst
    }

    /// The scalar path.
    #[test]
    fn the_scalar_path_matches_the_cpu() {
        compare(&RenderParams::default().prepare());
    }

    /// The exposure integrates over wavelength, and the print and the strip stay
    /// per channel.
    #[test]
    fn the_spectral_exposure_matches_the_cpu() {
        compare(
            &RenderParams {
                spectral: true,
                ..RenderParams::default()
            }
            .prepare(),
        );
    }

    /// The print integrates and the exposure does not.
    #[test]
    fn the_spectral_print_matches_the_cpu() {
        compare(
            &RenderParams {
                spectral_print: true,
                ..RenderParams::default()
            }
            .prepare(),
        );
    }

    /// All three stages, which is the full chain and the longest error path.
    #[test]
    fn the_whole_spectral_chain_matches_the_cpu() {
        compare(
            &RenderParams {
                spectral: true,
                spectral_print: true,
                spectral_scan: true,
                ..RenderParams::default()
            }
            .prepare(),
        );
    }

    /// Grain is a per-pixel fluctuation of the exposure, so it goes through the
    /// same dispatch — and, because the draw is ported rather than reused, it has
    /// to draw the same number. A draw that differed at all would differ by about
    /// 5e-3, fifty times the tolerance.
    #[test]
    fn grain_matches_the_cpu_on_the_scalar_path() {
        let grain = GrainField::new(WIDTH, HEIGHT, 36.0, 7);
        let finishing = Finishing {
            emulsion: None,
            grain: Some(&grain),
            ..Finishing::default()
        };
        compare_finished(
            &RenderParams::default().prepare(),
            &frame(),
            WIDTH,
            HEIGHT,
            &finishing,
        );
    }

    /// The same draw, through the longest model in the crate.
    #[test]
    fn grain_matches_the_cpu_through_the_spectral_chain() {
        let grain = GrainField::new(WIDTH, HEIGHT, 36.0, 0xDEAD_BEEF);
        let finishing = Finishing {
            emulsion: None,
            grain: Some(&grain),
            ..Finishing::default()
        };
        compare_finished(
            &RenderParams {
                spectral: true,
                spectral_print: true,
                spectral_scan: true,
                ..RenderParams::default()
            }
            .prepare(),
            &frame(),
            WIDTH,
            HEIGHT,
            &finishing,
        );
    }

    /// The transition rides on the curve, so a paper and a negative carry
    /// different ones through the same four numbers. That makes the packing a
    /// place a mistake would hide: swap the lanes and every default render still
    /// matches, because both are 4. This one is a paper at 10.
    #[test]
    fn a_paper_at_its_own_transition_matches_the_cpu() {
        let params = RenderParams {
            paper: kallotype_core::paper_stock("endura_premier_metallic")
                .expect("the measured paper"),
            ..RenderParams::default()
        };
        // The two transitions must actually differ, or the test proves nothing.
        let prepared = params.prepare();
        let model = prepared.scalar_model().expect("a scalar render");
        assert!(
            (model.transition[3] - model.transition[0]).abs() > 5.0,
            "paper {} against film {} — the lanes are not distinguishable",
            model.transition[3],
            model.transition[0]
        );
        compare_finished(&prepared, &frame(), WIDTH, HEIGHT, &Finishing::default());
    }

    /// Halation spreads light across pixels, which is the whole reason the chain
    /// exists: the halo has to land in the same place, and to fall off the same
    /// way, or the two backends disagree in a band around every highlight.
    #[test]
    fn halation_matches_the_cpu() {
        // Six micrometres per pixel puts the kernels at 1 and 5 pixels, wide
        // enough to reach across the edge and small enough to stay in frame.
        let halation = Halation::typical(6.0);
        let finishing = Finishing {
            emulsion: None,
            halation: Some(&halation),
            ..Finishing::default()
        };
        compare_finished(
            &RenderParams::default().prepare(),
            &frame(),
            WIDTH,
            HEIGHT,
            &finishing,
        );
    }

    /// The inhibitor diffuses before it acts, which is what turns a local
    /// suppression into an edge effect. Both halves of that have to match.
    #[test]
    fn couplers_match_the_cpu() {
        let couplers = Couplers::typical(6.0);
        let finishing = Finishing {
            couplers: Some(&couplers),
            ..Finishing::default()
        };
        compare_finished(
            &RenderParams::default().prepare(),
            &frame(),
            WIDTH,
            HEIGHT,
            &finishing,
        );
    }

    /// The emulsion's blur is the three-layer point spread of the film itself,
    /// and it runs on the exposure before anything is developed. Six micrometres
    /// per pixel puts the widest layer at 0.85 of a pixel — the resolution where
    /// a real scan starts to see it — and the narrowest at 0.52, so the three
    /// kernels are different lengths and any mix-up between them shows.
    #[test]
    fn the_emulsion_blur_matches_the_cpu() {
        let emulsion = crate::EmulsionBlur::measured(6.0);
        assert!(!emulsion.is_noop(), "the test needs a blur that acts");
        let finishing = Finishing {
            emulsion: Some(&emulsion),
            ..Finishing::default()
        };
        compare_finished(
            &RenderParams::default().prepare(),
            &frame(),
            WIDTH,
            HEIGHT,
            &finishing,
        );
    }

    /// Everything at once: five passes, the widest frame of error, and the case a
    /// user actually asks for.
    #[test]
    fn the_whole_chain_matches_the_cpu() {
        let grain = GrainField::new(WIDTH, HEIGHT, 36.0, 1234);
        let halation = Halation::typical(6.0);
        let couplers = Couplers::typical(6.0);
        let finishing = Finishing {
            emulsion: None,
            halation: Some(&halation),
            grain: Some(&grain),
            couplers: Some(&couplers),
        };
        compare_finished(
            &RenderParams {
                spectral: true,
                spectral_print: true,
                spectral_scan: true,
                ..RenderParams::default()
            }
            .prepare(),
            &frame(),
            WIDTH,
            HEIGHT,
            &finishing,
        );
    }

    /// Two ways to run the model — one dispatch, or a chain of passes — is two
    /// ways to disagree. With no spatial effect the chain must land on exactly
    /// the same pixels as the single dispatch: same arithmetic, stored to memory
    /// once instead of kept in a register, and f32 stores are exact.
    #[test]
    fn the_chain_agrees_with_the_single_dispatch() {
        let gpu = match Gpu::new() {
            Ok(gpu) => gpu,
            Err(_) => return,
        };
        let prepared = RenderParams {
            spectral: true,
            spectral_print: true,
            spectral_scan: true,
            ..RenderParams::default()
        }
        .prepare();
        let input = frame();
        let single = gpu
            .render_finished(&input, &prepared, WIDTH, HEIGHT, &Finishing::default())
            .expect("renders");
        let chained = gpu
            .run(
                &input,
                &prepared,
                WIDTH,
                HEIGHT,
                &Finishing::default(),
                true,
            )
            .expect("renders");

        for (index, (left, right)) in single.iter().zip(&chained).enumerate() {
            for channel in 0..3 {
                assert_eq!(
                    left[channel], right[channel],
                    "pixel {index} channel {channel}"
                );
            }
        }
    }

    /// An effect whose kernel would be thousands of taps is refused, not
    /// truncated: a shorter kernel is a smaller blur, which is a different
    /// photograph, and silently rendering it would be worse than falling back.
    #[test]
    fn an_impossibly_wide_kernel_is_refused() {
        let kernels = EffectKernels::build(Some(Halation::typical(0.001)), None, None);
        assert!(matches!(kernels, Err(GpuError::KernelTooWide(_))));
    }

    /// The spatial effects index by position, so a frame shape that does not
    /// describe the pixels is an error rather than a guess about the layout.
    #[test]
    fn a_frame_shape_that_does_not_match_is_refused() {
        let gpu = match Gpu::new() {
            Ok(gpu) => gpu,
            Err(_) => return,
        };
        let prepared = RenderParams::default().prepare();
        assert!(matches!(
            gpu.render_finished(&[[0.18; 3]; 4], &prepared, 3, 3, &Finishing::default()),
            Err(GpuError::Shape { .. })
        ));
    }

    /// The kernels are the CPU's own, and the offsets are where the shader is
    /// told to look. This runs without an adapter, which is where CI lives.
    #[test]
    fn the_kernels_are_the_cpus_kernels_at_the_stated_offsets() {
        let halation = Halation::typical(6.0);
        let couplers = Couplers::typical(6.0);
        let kernels = EffectKernels::build(Some(halation), Some(couplers), None).expect("kernels");

        let scatter = gaussian_kernel(halation.scatter.sigma_um / halation.pixel_um);
        let reflection = gaussian_kernel(halation.reflection.sigma_um / halation.pixel_um);
        let inhibitors = gaussian_kernel(couplers.sigma_um / couplers.pixel_um);

        assert_eq!(kernels.scatter.length, scatter.len());
        assert_eq!(kernels.reflection.length, reflection.len());
        assert_eq!(kernels.couplers.length, inhibitors.len());
        assert_eq!(kernels.scatter.offset, 0);
        assert_eq!(kernels.reflection.offset, scatter.len());
        assert_eq!(kernels.couplers.offset, scatter.len() + reflection.len());
        assert_eq!(
            kernels.floats.len(),
            scatter.len() + reflection.len() + inhibitors.len()
        );

        // f32 on the device, so the values agree to a rounding and not exactly.
        for (index, expected) in scatter.iter().enumerate() {
            let stored = f64::from(kernels.floats[index]);
            assert!((stored - expected).abs() < 1e-7, "{stored} vs {expected}");
        }
    }

    /// A baked table is a sampled cube and a dictionary is a per-pixel solve.
    /// Both must be refused rather than approximated.
    #[test]
    fn a_table_or_a_dictionary_is_refused() {
        let gpu = match Gpu::new() {
            Ok(gpu) => gpu,
            Err(_) => return,
        };
        let baked = RenderParams {
            spectral: true,
            lut_size: 17,
            ..RenderParams::default()
        }
        .prepare();
        assert!(matches!(
            gpu.render(&[[0.18; 3]], &baked),
            Err(GpuError::Unsupported(_))
        ));
    }

    /// The CPU writes the tables; the shader declares them. Nothing else checks
    /// that the two agree about how many there are.
    #[test]
    fn the_buffers_are_the_length_the_shaders_declare() {
        let prepared = RenderParams {
            spectral: true,
            spectral_print: true,
            spectral_scan: true,
            ..RenderParams::default()
        }
        .prepare();
        let model = prepared.spectral_model().expect("all three stages");
        assert_eq!(spectral_tables(&model).len(), TABLE_FLOATS);

        // Twenty-five lanes in `params.wgsl`, whatever the render asks for.
        let grain = GrainField::new(WIDTH, HEIGHT, 36.0, 1);
        let halation = Halation::typical(6.0);
        let couplers = Couplers::typical(6.0);
        let kernels = EffectKernels::build(Some(halation), Some(couplers), None).expect("kernels");
        for (spectral, finishing) in [
            (None, Finishing::default()),
            (
                Some(&model),
                Finishing {
                    emulsion: None,
                    halation: Some(&halation),
                    grain: Some(&grain),
                    couplers: Some(&couplers),
                },
            ),
        ] {
            let bytes = uniform(
                &model.scalar,
                spectral,
                finishing.grain,
                WIDTH as u32,
                HEIGHT as u32,
                finishing.halation.copied(),
                finishing.couplers.copied(),
                &kernels,
            );
            assert_eq!(bytes.len(), 28 * 16, "twenty-eight lanes");
        }
    }

    /// CI has no adapter, so the tests above skip there. This one does not: it
    /// replays the shader arithmetic from the same model the buffer writer uses
    /// and compares it against the CPU, which catches a table left out of the
    /// buffer even on a machine that cannot run the shader at all.
    #[test]
    fn the_replayed_shaders_agree_with_the_cpu() {
        let input = pixels();
        let width = input.len();
        for (name, params) in [
            ("scalar", RenderParams::default()),
            (
                "exposure",
                RenderParams {
                    spectral: true,
                    ..RenderParams::default()
                },
            ),
            (
                "print",
                RenderParams {
                    spectral_print: true,
                    ..RenderParams::default()
                },
            ),
            (
                "chain",
                RenderParams {
                    spectral: true,
                    spectral_print: true,
                    spectral_scan: true,
                    ..RenderParams::default()
                },
            ),
        ] {
            let prepared = params.prepare();
            let mut cpu = input.clone();
            render_pixels_finished(&mut cpu, &prepared, width, 1, &Finishing::default());
            let replayed = replay::render(&input, &prepared, None);

            let mut worst = 0.0_f64;
            for (expected, actual) in cpu.iter().zip(&replayed) {
                for channel in 0..3 {
                    worst = worst.max((expected[channel] - actual[channel]).abs());
                }
            }
            assert!(worst < 1e-9, "{name}: the replay differs by {worst:.2e}");
        }

        // And with grain, which is the one place the shader runs arithmetic the
        // CPU does not: a 64-bit generator on 32-bit halves.
        let grain = GrainField::new(WIDTH, HEIGHT, 36.0, 99);
        let finishing = Finishing {
            emulsion: None,
            grain: Some(&grain),
            ..Finishing::default()
        };
        for (name, params) in [
            ("scalar+grain", RenderParams::default()),
            (
                "chain+grain",
                RenderParams {
                    spectral: true,
                    spectral_print: true,
                    spectral_scan: true,
                    ..RenderParams::default()
                },
            ),
        ] {
            let prepared = params.prepare();
            let mut cpu = frame();
            render_pixels_finished(&mut cpu, &prepared, WIDTH, HEIGHT, &finishing);
            let replayed = replay::render(&frame(), &prepared, Some(&grain));

            let mut worst = 0.0_f64;
            for (expected, actual) in cpu.iter().zip(&replayed) {
                for channel in 0..3 {
                    worst = worst.max((expected[channel] - actual[channel]).abs());
                }
            }
            assert!(worst < 1e-9, "{name}: the replay differs by {worst:.2e}");
        }
    }
}

#[cfg(test)]
mod timing {
    use super::*;
    use kallotype_core::{RenderParams, render_pixels_finished};

    /// Not an assertion, a measurement: how fast the two backends actually are,
    /// transfer included, on a frame big enough to matter.
    ///
    /// Ignored by default because it takes seconds and because a GPU benchmark on
    /// a CI runner measures the absence of a GPU.
    #[test]
    #[ignore = "timing, not correctness; run with --ignored --nocapture"]
    fn how_fast_is_it_actually() {
        const WIDTH: usize = 1920;
        const HEIGHT: usize = 1080;
        let gpu = Gpu::new().expect("a GPU adapter");
        let mut pixels = Vec::with_capacity(WIDTH * HEIGHT);
        for y in 0..HEIGHT {
            for x in 0..WIDTH {
                let a = x as f64 / WIDTH as f64;
                let b = y as f64 / HEIGHT as f64;
                pixels.push([a, b, (a * b).sqrt()]);
            }
        }
        let grain = GrainField::new(WIDTH, HEIGHT, 36.0, 1);
        let halation = Halation::typical(6.0);
        let couplers = Couplers::typical(6.0);

        for (name, params, finishing) in [
            ("scalar", RenderParams::default(), Finishing::default()),
            (
                "spectral",
                RenderParams {
                    spectral: true,
                    spectral_print: true,
                    spectral_scan: true,
                    ..RenderParams::default()
                },
                Finishing::default(),
            ),
            (
                "spectral+grain",
                RenderParams {
                    spectral: true,
                    spectral_print: true,
                    spectral_scan: true,
                    ..RenderParams::default()
                },
                Finishing {
                    grain: Some(&grain),
                    ..Finishing::default()
                },
            ),
            (
                "spectral+all",
                RenderParams {
                    spectral: true,
                    spectral_print: true,
                    spectral_scan: true,
                    ..RenderParams::default()
                },
                Finishing {
                    emulsion: None,
                    halation: Some(&halation),
                    grain: Some(&grain),
                    couplers: Some(&couplers),
                },
            ),
        ] {
            let prepared = params.prepare();
            let mut cpu = pixels.clone();
            let start = std::time::Instant::now();
            render_pixels_finished(&mut cpu, &prepared, WIDTH, HEIGHT, &finishing);
            let cpu_time = start.elapsed();

            let start = std::time::Instant::now();
            let gpu_out = gpu
                .render_finished(&pixels, &prepared, WIDTH, HEIGHT, &finishing)
                .expect("renders");
            let gpu_time = start.elapsed();

            println!(
                "{name:15} {} px: cpu {:.1} ms, gpu {:.1} ms (upload + dispatch + readback), ratio {:.2}x",
                pixels.len(),
                cpu_time.as_secs_f64() * 1e3,
                gpu_time.as_secs_f64() * 1e3,
                cpu_time.as_secs_f64() / gpu_time.as_secs_f64()
            );
            assert_eq!(gpu_out.len(), cpu.len());
        }
    }
}
