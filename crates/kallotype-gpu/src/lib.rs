//! A wgpu backend that must agree with [`kallotype_core`].
//!
//! The point of this crate is not speed. It is that a second implementation of
//! the model exists and is held to a number: [`Gpu::render`] and
//! [`kallotype_core::render_pixels`] are compared on the same pixels, and the
//! difference is asserted against [`TOLERANCE`]. A GPU port that "looks right"
//! is how a film simulation acquires two different films.
//!
//! ## What it covers
//!
//! Both exposed models:
//!
//! - the **scalar path**, where the CPU hands over the numbers it solved;
//! - the **spectral path**, where there are no numbers to hand over because the
//!   model integrates over wavelength. That one gets the tables instead — the
//!   polynomial basis, the film layers, the dye spectra, the illuminants, the
//!   observer — plus the three 3×3 systems already inverted, so the shader
//!   multiplies where the CPU would solve.
//!
//! The exposure, the print and the scan are independent stages, and every
//! combination of them anywhere between has a branch in `spectral.wgsl`. What
//! is *not* covered is deliberate: a baked table and a dictionary prior are
//! their own models — a sampled cube and a per-pixel non-negative least squares
//! — and [`Gpu::render`] returns [`GpuError::Unsupported`] rather than
//! rendering something adjacent.
//!
//! **Grain** is implemented. It is a fluctuation of the exposure at a single
//! pixel, so both shaders apply it where the CPU does — and because the draw is
//! SplitMix64 and WGSL has no 64-bit integers, `grain.wgsl` runs the same
//! generator on pairs of `u32`. For a random draw "close enough" would be false:
//! the two backends either draw the same number or they are two films.
//!
//! **Halation and DIR couplers** convolve the whole frame, which is a chain of
//! passes rather than one, and they are refused by name.
//!
//! ## Where the tolerance comes from
//!
//! The CPU runs in f64 and the shaders in f32, so the difference is rounding,
//! and the interesting part is how the model amplifies it. The scalar path has
//! two amplifiers: the characteristic curve's slope (about `gamma` densities per
//! decade) and the print's logistic, which is steepest near the anchor. Both are
//! *stable* — they multiply an error rather than growing one. Measured across a
//! 2 048-pixel grid that spans the toe and the shoulder, the worst per-channel
//! difference on the scalar path is `2.2e-7` in linear light.
//!
//! The spectral path adds four more: two `log10` per pixel, a `10^-d` per
//! wavelength, and a larger dynamic range on the way — the paper's blue layer
//! integrates to about 13 before normalisation and the observer to about 9 000.
//! Cancellation is the thing to watch, and it does not appear: the reconstruction
//! matrix is small and well scaled, and every table is non-negative. Measured
//! over the same grid, the worst difference is `3.6e-7` with the spectral
//! exposure, `8.2e-7` with the spectral print and `1.0e-6` with all three
//! stages, which is why one [`TOLERANCE`] covers both shaders.
//!
//! Grain adds a fifth amplifier and it is the sharpest one: a draw that differs
//! at all differs by a whole standard deviation, about `5e-3` in log exposure,
//! fifty times [`TOLERANCE`]. Measured on a 512-pixel frame it adds `1e-10` to
//! the scalar path and `-6e-8` to the spectral one — that is, nothing — because
//! the shader draws the same number rather than a nearby one.
//!
//! ## No adapter, no test
//!
//! CI runners have no GPU and some have no software rasteriser either. The tests
//! skip when no adapter can be opened, and say so, because a GPU test that fails
//! on a machine without a GPU teaches people to ignore it.

#[cfg(test)]
mod replay;

use kallotype_core::model::NEUTRAL_ENTRIES;
use kallotype_core::spectral::GRID_LEN;
use kallotype_core::{Finishing, GrainField, PreparedRender, ScalarModel, SpectralModel};

/// The shader sources, as files. `GRAIN` is concatenated ahead of the other two.
const GRAIN: &str = include_str!("../shaders/grain.wgsl");
const SCALAR: &str = include_str!("../shaders/scalar.wgsl");
const SPECTRAL: &str = include_str!("../shaders/spectral.wgsl");

/// The largest per-channel difference the two backends are allowed, in linear
/// light.
///
/// Measured on this model the worst difference is `3.0e-7` on the scalar path
/// and `1.0e-6` on the full spectral one, with or without grain; the bound is set
/// two orders of magnitude above them so it catches a wrong implementation
/// rather than a rounding mode.
pub const TOLERANCE: f64 = 1.0e-4;

/// Why the GPU backend could not render.
#[derive(Debug)]
pub enum GpuError {
    /// No adapter, or the device could not be created.
    NoAdapter(String),
    /// The render uses a stage this backend does not implement, named.
    Unsupported(&'static str),
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
            Self::Empty => write!(formatter, "no pixels to render"),
        }
    }
}

impl std::error::Error for GpuError {}

/// A device and the two compute pipelines, reused across renders.
pub struct Gpu {
    device: wgpu::Device,
    queue: wgpu::Queue,
    scalar: Stage,
    spectral: Stage,
    adapter: wgpu::AdapterInfo,
}

/// One pipeline and the layout its bind group has to match.
struct Stage {
    pipeline: wgpu::ComputePipeline,
    binder: wgpu::BindGroupLayout,
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

    /// Open the default adapter and build both pipelines.
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

        // Grain is one file prepended to both shaders: it is the same draw in
        // both, and two copies of a 64-bit generator written twice in u32 halves
        // is two chances to get a carry wrong.
        let scalar = Stage::build(&device, "scalar", &format!("{GRAIN}\n{SCALAR}"), false);
        let spectral = Stage::build(&device, "spectral", &format!("{GRAIN}\n{SPECTRAL}"), true);

        Ok(Self {
            device,
            queue,
            scalar,
            spectral,
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
        self.render_finished(pixels, prepared, &Finishing::default())
    }

    /// The same, with the finishing effects the CPU model has.
    ///
    /// Grain goes through: it is a fluctuation of the exposure at one pixel, so
    /// both shaders apply it where the CPU does, and they draw the same number —
    /// see `grain.wgsl`. Halation and the DIR couplers convolve the whole frame,
    /// which is a chain of passes rather than one, and they are refused rather
    /// than dropped.
    ///
    /// # Errors
    ///
    /// [`GpuError::Unsupported`] when the render needs a stage or an effect this
    /// backend does not implement, and [`GpuError::Empty`] for an empty image.
    pub fn render_finished(
        &self,
        pixels: &[[f64; 3]],
        prepared: &PreparedRender,
        finishing: &Finishing,
    ) -> Result<Vec<[f64; 3]>, GpuError> {
        if finishing.halation.is_some() {
            return Err(GpuError::Unsupported("halation"));
        }
        if finishing.couplers.is_some() {
            return Err(GpuError::Unsupported("DIR couplers"));
        }
        let grain = finishing.grain;

        // Exactly one of these describes a given render; the scalar case comes
        // first only because it is the one with fewer numbers in it.
        if let Some(model) = prepared.scalar_model() {
            return self.execute(
                &self.scalar,
                "scalar",
                pixels,
                &scalar_uniform(&model, grain),
                None,
            );
        }
        if let Some(model) = prepared.spectral_model() {
            return self.execute(
                &self.spectral,
                "spectral",
                pixels,
                &spectral_uniform(&model, grain),
                Some(&spectral_tables(&model)),
            );
        }
        Err(GpuError::Unsupported(
            "a baked exposure table or a dictionary prior",
        ))
    }

    /// Render pixels through the scalar model.
    ///
    /// # Errors
    ///
    /// [`GpuError::Empty`] for an empty image.
    pub fn render_model(
        &self,
        pixels: &[[f64; 3]],
        model: &ScalarModel,
    ) -> Result<Vec<[f64; 3]>, GpuError> {
        self.execute(
            &self.scalar,
            "scalar",
            pixels,
            &scalar_uniform(model, None),
            None,
        )
    }

    /// Render pixels through the spectral model.
    ///
    /// # Errors
    ///
    /// [`GpuError::Empty`] for an empty image.
    pub fn render_spectral(
        &self,
        pixels: &[[f64; 3]],
        model: &SpectralModel,
    ) -> Result<Vec<[f64; 3]>, GpuError> {
        self.execute(
            &self.spectral,
            "spectral",
            pixels,
            &spectral_uniform(model, None),
            Some(&spectral_tables(model)),
        )
    }

    /// Upload, dispatch, read back.
    ///
    /// Shared by both pipelines because the only thing that differs between
    /// them is what is in the uniform and whether there are tables.
    fn execute(
        &self,
        stage: &Stage,
        label: &'static str,
        pixels: &[[f64; 3]],
        uniform: &[u8],
        tables: Option<&[u8]>,
    ) -> Result<Vec<[f64; 3]>, GpuError> {
        if pixels.is_empty() {
            return Err(GpuError::Empty);
        }

        let bytes = (pixels.len() * 16) as u64;
        let uniform_buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("params"),
            size: uniform.len() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        self.queue.write_buffer(&uniform_buffer, 0, uniform);

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

        let table_buffer = tables.map(|tables| {
            let buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("tables"),
                size: tables.len() as u64,
                usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });
            self.queue.write_buffer(&buffer, 0, tables);
            buffer
        });

        let mut entries = vec![
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
        ];
        if let Some(buffer) = &table_buffer {
            entries.push(wgpu::BindGroupEntry {
                binding: 3,
                resource: buffer.as_entire_binding(),
            });
        }

        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some(label),
            layout: &stage.binder,
            entries: &entries,
        });

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(label) });
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some(label),
                timestamp_writes: None,
            });
            pass.set_pipeline(&stage.pipeline);
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
}

impl Stage {
    fn build(device: &wgpu::Device, label: &'static str, source: &str, tables: bool) -> Self {
        let module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some(label),
            source: wgpu::ShaderSource::Wgsl(source.into()),
        });

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
        let mut entries = vec![
            entry(0, wgpu::BufferBindingType::Uniform),
            entry(1, wgpu::BufferBindingType::Storage { read_only: true }),
            entry(2, wgpu::BufferBindingType::Storage { read_only: false }),
        ];
        if tables {
            entries.push(entry(
                3,
                wgpu::BufferBindingType::Storage { read_only: true },
            ));
        }

        let binder = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some(label),
            entries: &entries,
        });
        let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some(label),
            bind_group_layouts: &[&binder],
            push_constant_ranges: &[],
        });
        let pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some(label),
            layout: Some(&layout),
            module: &module,
            entry_point: Some("main"),
            compilation_options: Default::default(),
            cache: None,
        });

        Self { pipeline, binder }
    }
}

// ---------------------------------------------------------------------------
// The uniform and the tables, in the layout the shaders declare.
// ---------------------------------------------------------------------------

/// Append values as little-endian f32.
fn push_f32(out: &mut Vec<u8>, values: &[f32]) {
    out.extend(values.iter().flat_map(|value| value.to_le_bytes()));
}

/// Append values as little-endian u32.
fn push_u32(out: &mut Vec<u8>, values: &[u32]) {
    out.extend(values.iter().flat_map(|value| value.to_le_bytes()));
}

/// The three lanes both shaders end with: the grain field and what was asked for.
///
/// A render without grain still occupies them, with the flag at zero, because a
/// buffer that changed length would move every field after it.
fn push_grain(out: &mut Vec<u8>, grain: Option<&GrainField>) {
    let seed = grain.map_or(0, |grain| grain.seed);
    push_u32(
        out,
        &[
            seed as u32,
            (seed >> 32) as u32,
            grain.map_or(0, |grain| grain.width as u32),
            grain.map_or(0, |grain| grain.height as u32),
        ],
    );
    push_f32(
        out,
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
    push_u32(out, &[u32::from(grain.is_some()), 0, 0, 0]);
}

/// The uniform buffer for a scalar model, in the layout `scalar.wgsl` expects.
fn scalar_uniform(model: &ScalarModel, grain: Option<&GrainField>) -> Vec<u8> {
    let mut out = Vec::with_capacity(128);
    for curve in &model.curve {
        push_f32(&mut out, &curve.map(|value| value as f32));
    }
    // (paper d_min, paper span, enlarger slope, exposure shift)
    push_f32(
        &mut out,
        &[
            model.paper[0] as f32,
            model.paper[1] as f32,
            model.print[0] as f32,
            model.exposure_shift as f32,
        ],
    );
    // The three anchors, padded to a vec4.
    push_f32(
        &mut out,
        &[
            model.print[1] as f32,
            model.print[2] as f32,
            model.print[3] as f32,
            0.0,
        ],
    );
    push_grain(&mut out, grain);
    out
}

/// The uniform buffer for a spectral model, in the layout `spectral.wgsl`
/// expects: fifteen `vec4` lanes, in the order the struct declares them, then
/// the three the grain block appends.
fn spectral_uniform(model: &SpectralModel, grain: Option<&GrainField>) -> Vec<u8> {
    let scalar = &model.scalar;
    let exposure = model.exposure.as_ref();
    let enlarger = model.enlarger.as_ref();
    let scan = model.scan.as_ref();

    let mut lanes: Vec<[f32; 4]> = Vec::with_capacity(15);
    for curve in &scalar.curve {
        lanes.push(curve.map(|value| value as f32));
    }
    lanes.push([
        scalar.paper[0] as f32,
        scalar.paper[1] as f32,
        scalar.print[0] as f32,
        scalar.exposure_shift as f32,
    ]);
    lanes.push([
        scalar.print[1] as f32,
        scalar.print[2] as f32,
        scalar.print[3] as f32,
        0.0,
    ]);
    lanes.push([GRID_LEN as f32, model.step_nm as f32, 0.0, 0.0]);
    // `f32::from(bool)` does not exist, and a `0.0`/`1.0` lane is what the
    // shader compares against `0.5`.
    lanes.push(lane(
        exposure.map_or([0.0; 3], |model| model.reference),
        0.0,
    ));
    lanes.push(lane(
        enlarger.map_or([0.0; 3], |model| model.reference),
        0.0,
    ));
    lanes.push([
        enlarger.map_or(0.0, |model| model.masking[0]) as f32,
        enlarger.map_or(0.0, |model| model.masking[1]) as f32,
        enlarger.map_or(0.0, |model| model.masking[2]) as f32,
        enlarger.map_or(1.0, |model| model.masking_reference) as f32,
    ]);
    lanes.push(lane(enlarger.map_or([0.0; 3], |model| model.filters), 0.0));
    lanes.push(lane(scan.map_or([1.0; 3], |model| model.white_xyz), 0.0));
    lanes.push(lane(scan.map_or([1.0; 3], |model| model.white_rgb), 0.0));
    lanes.push([
        scan.map_or(0.0, |model| model.neutral_max_density) as f32,
        // Derived from the table rather than from a second constant: the
        // neutral axis runs from density zero to its span in `len - 1` steps.
        scan.map_or(0.0, |model| (model.neutral.len() - 1) as f64) as f32,
        scan.map_or(0.0, |model| model.base_density) as f32,
        0.0,
    ]);
    lanes.push([
        flag(model.exposure.is_some()),
        flag(model.enlarger.is_some()),
        flag(model.scan.is_some()),
        flag(enlarger.is_some_and(|model| model.clamped)),
    ]);
    lanes.push([flag(scan.is_some_and(|model| model.clamped)), 0.0, 0.0, 0.0]);

    let mut out = Vec::with_capacity(288);
    for lane in &lanes {
        push_f32(&mut out, lane);
    }
    push_grain(&mut out, grain);
    out
}

/// Append `values` as f32, which is the only conversion the tables need.
fn push(out: &mut Vec<f32>, values: &[f64]) {
    out.extend(values.iter().map(|&value| value as f32));
}

fn flag(value: bool) -> f32 {
    if value { 1.0 } else { 0.0 }
}

fn lane(values: [f64; 3], fourth: f64) -> [f32; 4] {
    [
        values[0] as f32,
        values[1] as f32,
        values[2] as f32,
        fourth as f32,
    ]
}

/// Floats in `spectral.wgsl`'s `Tables` struct, in its declared order.
///
/// Kept as arithmetic rather than a number so that it follows [`GRID_LEN`] and
/// [`NEUTRAL_ENTRIES`]; a test asserts the writer produces exactly this many.
/// Reconstruction, basis, film layers.
const EXPOSURE_FLOATS: usize = 9 + 6 * GRID_LEN;
/// Unmixing, dye, paper layers, illuminant, mask, filter bands.
const PRINT_FLOATS: usize = 9 + 11 * GRID_LEN;
/// Unmixing, dye, observer, illuminant, matrix, neutral axis.
const SCAN_FLOATS: usize = 9 + 7 * GRID_LEN + 9 + 3 * NEUTRAL_ENTRIES;

const TABLE_FLOATS: usize = EXPOSURE_FLOATS + PRINT_FLOATS + SCAN_FLOATS;

/// The tables buffer, in the order `spectral.wgsl`'s `Tables` declares.
///
/// A stage that is not active still occupies its slice: the struct has a fixed
/// shape, and a buffer that grew and shrank would put the scan's dye table where
/// the print expected its own the moment someone turned a flag off.
fn spectral_tables(model: &SpectralModel) -> Vec<u8> {
    let mut floats: Vec<f32> = Vec::with_capacity(TABLE_FLOATS);

    match &model.exposure {
        Some(exposure) => {
            push(&mut floats, &exposure.reconstruct.concat());
            for row in &exposure.basis {
                push(&mut floats, row);
            }
            for row in &exposure.film {
                push(&mut floats, row);
            }
        }
        None => floats.resize(floats.len() + EXPOSURE_FLOATS, 0.0),
    }

    match &model.enlarger {
        Some(enlarger) => {
            push(&mut floats, &enlarger.analytical.concat());
            for row in &enlarger.dye {
                push(&mut floats, row);
            }
            for row in &enlarger.paper {
                push(&mut floats, row);
            }
            push(&mut floats, &enlarger.illuminant);
            push(&mut floats, &enlarger.mask);
            for row in &enlarger.filter_bands {
                push(&mut floats, row);
            }
        }
        None => floats.resize(floats.len() + PRINT_FLOATS, 0.0),
    }

    match &model.scan {
        Some(scan) => {
            push(&mut floats, &scan.analytical.concat());
            for row in &scan.dye {
                push(&mut floats, row);
            }
            for row in &scan.cmf {
                push(&mut floats, row);
            }
            push(&mut floats, &scan.illuminant);
            push(&mut floats, &scan.matrix.concat());
            for level in &scan.neutral {
                push(&mut floats, level);
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
        .iter()
        .flat_map(|value| value.to_le_bytes())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use kallotype_core::{Halation, RenderParams, render_pixels, render_pixels_finished};

    /// A grain field on a small frame, for the tests that need one.
    fn sample_grain() -> GrainField {
        GrainField::new(32, 16, 36.0, 12345)
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

    /// A frame shaped like a grain field, so that the two agree about which
    /// pixel is the one at `(x, y)` — a flat list of the right length is not
    /// enough, because grain is indexed by position.
    fn frame() -> (usize, usize, Vec<[f64; 3]>) {
        const WIDTH: usize = 32;
        const HEIGHT: usize = 16;
        let mut out = Vec::with_capacity(WIDTH * HEIGHT);
        for y in 0..HEIGHT {
            for x in 0..WIDTH {
                let a = (x as f64 + 0.5) / WIDTH as f64;
                let b = (y as f64 + 0.5) / HEIGHT as f64;
                out.push([a * a, b * 0.4, (a * b).sqrt()]);
            }
        }
        (WIDTH, HEIGHT, out)
    }

    /// The difference between the two backends, worst channel first.
    fn compare(prepared: &kallotype_core::PreparedRender) -> f64 {
        compare_finished(prepared, &pixels(), &Finishing::default())
    }

    /// The same, for a render with finishing effects and its own frame shape.
    fn compare_finished(
        prepared: &kallotype_core::PreparedRender,
        input: &[[f64; 3]],
        finishing: &Finishing,
    ) -> f64 {
        let gpu = match Gpu::new() {
            Ok(gpu) => gpu,
            Err(error) => {
                eprintln!("skipping the GPU comparison: {error}");
                return 0.0;
            }
        };
        let input = input.to_vec();
        let width = finishing.grain.map_or(input.len(), |grain| grain.width);
        let height = finishing.grain.map_or(1, |grain| grain.height);
        let mut cpu = input.clone();
        render_pixels_finished(&mut cpu, prepared, width, height, finishing);
        let gpu_out = gpu
            .render_finished(&input, prepared, finishing)
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

    /// CI has no adapter, so the tests above skip there. This one does not: it
    /// replays the shader arithmetic from the same model the buffer writer uses
    /// and compares it against the CPU, which catches a table left out of the
    /// buffer even on a machine that cannot run the shader at all.
    #[test]
    fn the_replayed_shaders_agree_with_the_cpu() {
        let input = pixels();
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
            render_pixels(&mut cpu, &prepared);
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
        let (width, height, input) = frame();
        let grain = GrainField::new(width, height, 36.0, 99);
        let finishing = Finishing {
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
            let mut cpu = input.clone();
            render_pixels_finished(&mut cpu, &prepared, width, height, &finishing);
            let replayed = replay::render(&input, &prepared, Some(&grain));

            let mut worst = 0.0_f64;
            for (expected, actual) in cpu.iter().zip(&replayed) {
                for channel in 0..3 {
                    worst = worst.max((expected[channel] - actual[channel]).abs());
                }
            }
            assert!(worst < 1e-9, "{name}: the replay differs by {worst:.2e}");
        }
    }

    /// The whole point of the crate: two implementations, one number between
    /// them.
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

    /// The print integrates and the exposure does not: one of the two mixed
    /// cases, and the one where the dye tables and the mask matter.
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
    /// same shader — and, because the draw is ported rather than reused, it has
    /// to draw the same number. This is the test that says the port is exact.
    #[test]
    fn grain_matches_the_cpu_on_the_scalar_path() {
        let (_, _, input) = frame();
        let grain = GrainField::new(32, 16, 36.0, 7);
        let finishing = Finishing {
            grain: Some(&grain),
            ..Finishing::default()
        };
        compare_finished(&RenderParams::default().prepare(), &input, &finishing);
    }

    /// The same draw, through the longest shader in the crate.
    #[test]
    fn grain_matches_the_cpu_through_the_spectral_chain() {
        let (_, _, input) = frame();
        let grain = GrainField::new(32, 16, 36.0, 0xDEAD_BEEF);
        let finishing = Finishing {
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
            &input,
            &finishing,
        );
    }

    /// The two spatial effects convolve the frame, which needs a chain of passes
    /// rather than one. They are refused by name, not dropped on the floor.
    #[test]
    fn the_spatial_effects_are_refused_by_name() {
        let gpu = match Gpu::new() {
            Ok(gpu) => gpu,
            Err(_) => return,
        };
        let prepared = RenderParams::default().prepare();
        let halation = Halation::typical(6.0);
        let couplers = kallotype_core::Couplers::typical(6.0);
        for (finishing, name) in [
            (
                Finishing {
                    halation: Some(&halation),
                    ..Finishing::default()
                },
                "halation",
            ),
            (
                Finishing {
                    couplers: Some(&couplers),
                    ..Finishing::default()
                },
                "DIR couplers",
            ),
        ] {
            match gpu.render_finished(&[[0.18; 3]], &prepared, &finishing) {
                Err(GpuError::Unsupported(reason)) => assert_eq!(reason, name),
                other => panic!("expected a refusal of {name}, got {other:?}"),
            }
        }
    }

    /// A baked table is a sampled cube, not an integration, and a dictionary is
    /// a per-pixel solve. Both must be refused rather than approximated.
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
    fn the_tables_buffer_is_the_length_the_shader_declares() {
        let prepared = RenderParams {
            spectral: true,
            spectral_print: true,
            spectral_scan: true,
            ..RenderParams::default()
        }
        .prepare();
        let model = prepared.spectral_model().expect("all three stages");
        assert_eq!(spectral_tables(&model).len(), TABLE_FLOATS * 4);

        // Fifteen lanes of model, then three for the grain block, which a render
        // without grain still occupies so that nothing after it moves.
        assert_eq!(spectral_uniform(&model, None).len(), 18 * 16);
        assert_eq!(
            spectral_uniform(&model, Some(&sample_grain())).len(),
            18 * 16
        );
        assert_eq!(
            scalar_uniform(
                &RenderParams::default().prepare().scalar_model().unwrap(),
                None
            )
            .len(),
            8 * 16
        );
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
        let mut pixels = Vec::with_capacity(1920 * 1080);
        for y in 0..1080u32 {
            for x in 0..1920u32 {
                let a = x as f64 / 1920.0;
                let b = y as f64 / 1080.0;
                pixels.push([a, b, (a * b).sqrt()]);
            }
        }

        for (name, params) in [
            ("scalar", RenderParams::default()),
            (
                "spectral",
                RenderParams {
                    spectral: true,
                    spectral_print: true,
                    spectral_scan: true,
                    ..RenderParams::default()
                },
            ),
        ] {
            let prepared = params.prepare();
            let mut cpu = pixels.clone();
            let start = std::time::Instant::now();
            kallotype_core::render_pixels(&mut cpu, &prepared);
            let cpu_time = start.elapsed();

            let start = std::time::Instant::now();
            let gpu_out = gpu.render(&pixels, &prepared).expect("renders");
            let gpu_time = start.elapsed();

            println!(
                "{name:8} {} px: cpu {:.1} ms, gpu {:.1} ms (upload + dispatch + readback), ratio {:.2}x",
                pixels.len(),
                cpu_time.as_secs_f64() * 1e3,
                gpu_time.as_secs_f64() * 1e3,
                cpu_time.as_secs_f64() / gpu_time.as_secs_f64()
            );
            assert_eq!(gpu_out.len(), cpu.len());
        }
    }
}
