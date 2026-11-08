//! `kalo render` — apply the model to a whole image.

use std::path::Path;

use kallotype_core::{
    Couplers, EmulsionBlur, Finishing, GrainField, Halation, Metering, render_pixels_finished,
};
use kallotype_io::{InputEncoding, load, save};

use crate::cli::{Exposure, RenderArgs};
use crate::commands::common::{Rendering, print_report, resolve};
use crate::error::CliError;

/// Who did the work.
pub enum Backend {
    /// The `kallotype-core` model, in f64.
    Cpu,
    /// The device, as wgpu describes it. Only constructed in a build with the
    /// `gpu` feature, which is why it is allowed to be dead code without it.
    #[cfg_attr(not(feature = "gpu"), allow(dead_code))]
    Gpu(String),
}

impl std::fmt::Display for Backend {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Cpu => write!(formatter, "cpu"),
            Self::Gpu(name) => write!(formatter, "gpu — {name}"),
        }
    }
}

/// Render the pixels, on the GPU if asked and possible, on the CPU otherwise.
///
/// The fallback is deliberate and loud. A machine with no adapter, or a render
/// the backend does not implement, gets a warning and a correct image, not an
/// error and not a silently different one.
#[cfg(feature = "gpu")]
fn render_pixels(
    pixels: &mut [[f64; 3]],
    prepared: &kallotype_core::PreparedRender,
    width: usize,
    height: usize,
    finishing: &Finishing,
    on_gpu: bool,
) -> Result<Backend, CliError> {
    if !on_gpu {
        return Ok(render_on_cpu(pixels, prepared, width, height, finishing));
    }

    let gpu = match kallotype_gpu::Gpu::new() {
        Ok(gpu) => gpu,
        Err(error) => {
            eprintln!("warning: {error}; rendering on the cpu");
            return Ok(render_on_cpu(pixels, prepared, width, height, finishing));
        }
    };

    match gpu.render_finished(pixels, prepared, width, height, finishing) {
        Ok(rendered) => {
            pixels.copy_from_slice(&rendered);
            Ok(Backend::Gpu(gpu.describe()))
        }
        // The backend names what it cannot do — a table, a dictionary — and
        // asking it is what decides: the CLI keeps no second list of supported
        // stages to drift out of step with the crate's.
        Err(kallotype_gpu::GpuError::Unsupported(stage)) => {
            eprintln!(
                "warning: the gpu backend does not implement {stage} yet; rendering on the cpu"
            );
            Ok(render_on_cpu(pixels, prepared, width, height, finishing))
        }
        Err(error) => Err(CliError::Gpu {
            message: error.to_string(),
        }),
    }
}

/// Without the feature there is no device to ask for, so the render is the CPU's
/// and the report says so. A build that cannot honour the default must not fail
/// because of it.
#[cfg(not(feature = "gpu"))]
fn render_pixels(
    pixels: &mut [[f64; 3]],
    prepared: &kallotype_core::PreparedRender,
    width: usize,
    height: usize,
    finishing: &Finishing,
    on_gpu: bool,
) -> Result<Backend, CliError> {
    if on_gpu {
        eprintln!(
            "warning: this build has no GPU backend (rebuild without              --no-default-features); rendering on the cpu"
        );
    }
    Ok(render_on_cpu(pixels, prepared, width, height, finishing))
}

fn render_on_cpu(
    pixels: &mut [[f64; 3]],
    prepared: &kallotype_core::PreparedRender,
    width: usize,
    height: usize,
    finishing: &Finishing,
) -> Backend {
    render_pixels_finished(pixels, prepared, width, height, finishing);
    Backend::Cpu
}

/// Read the input, from a camera raw when it is one and the feature is on.
///
/// A raw file is scene-referred linear by construction, so `--input-encoding`
/// does not apply to it: the value is taken as the file's own, and a user who
/// asked for `srgb` on a `.nef` is not obeyed, because obeying would apply a
/// transfer curve to data that never had one.
// A short list, and only for the error message: without the `raw` feature there
// is no decoder to ask, and "unsupported image format" is a poor answer to
// someone who passed a camera file.
#[cfg(not(feature = "raw"))]
const RAW_EXTENSIONS: &[&str] = &[
    "3fr", "arw", "cr2", "cr3", "dng", "iiq", "nef", "nrw", "orf", "pef", "raf", "rw2", "srw",
];

#[cfg(not(feature = "raw"))]
fn looks_like_raw(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| RAW_EXTENSIONS.contains(&extension.to_ascii_lowercase().as_str()))
}

fn read_input(path: &Path, encoding: InputEncoding) -> Result<kallotype_io::Image, CliError> {
    #[cfg(feature = "raw")]
    if kallotype_raw::handles(path) {
        return kallotype_raw::load(path).map_err(|source| CliError::Raw {
            path: path.to_path_buf(),
            message: source.to_string(),
        });
    }
    #[cfg(not(feature = "raw"))]
    if looks_like_raw(path) {
        return Err(CliError::Raw {
            path: path.to_path_buf(),
            message: "this build has no raw decoder; rebuild with `--features raw`, or \
                      convert the file and pass --input-encoding linear"
                .to_string(),
        });
    }
    load(path, encoding).map_err(|source| CliError::Read {
        path: path.to_path_buf(),
        source,
    })
}

/// Run the subcommand.
pub fn run(args: RenderArgs) -> Result<(), CliError> {
    let selection = resolve(&args.stock)?;

    let mut image = read_input(&args.input, args.input_encoding.into())?;
    let (width, height) = (image.width, image.height);

    // The meter reads the frame, and the offset it solves is part of the
    // parameters, so it runs between the decode and the prepare.
    let (exposure_ev, metering) = match args.ev {
        Exposure::Stops(ev) => (ev, None),
        Exposure::Auto => {
            let metered = Metering::of(&image.pixels);
            (metered.ev, Some(metered))
        }
    };
    let params = selection.render_params(exposure_ev);
    let prepared = selection.prepare(exposure_ev)?;

    let pixel_um = args.frame_mm * 1000.0 / width.max(1) as f64;
    // The field takes its grain density from the stock: the measured one differs
    // by a factor of nine between its layers, and a stock without a measurement
    // falls back to the placeholder.
    let grain = args.grain.then(|| {
        GrainField::for_stock(
            width as usize,
            height as usize,
            args.frame_mm,
            args.grain_seed,
            selection.film,
        )
    });
    let emulsion = (!args.no_emulsion).then(|| EmulsionBlur::for_stock(selection.film, pixel_um));
    let halation = args.halation.then(|| Halation::typical(pixel_um));
    let couplers = args.couplers.then(|| Couplers::typical(pixel_um));
    let finishing = Finishing {
        emulsion: emulsion.as_ref(),
        halation: halation.as_ref(),
        grain: grain.as_ref(),
        couplers: couplers.as_ref(),
    };
    let backend = render_pixels(
        &mut image.pixels,
        &prepared,
        width as usize,
        height as usize,
        &finishing,
        args.gpu,
    )?;

    ensure_parent(&args.output)?;

    save(&args.output, &image).map_err(|source| CliError::Write {
        path: args.output.clone(),
        source,
    })?;

    print_report(
        &params,
        &prepared,
        width,
        height,
        &Rendering {
            grain: grain.as_ref(),
            emulsion: emulsion.as_ref(),
            halation: halation.as_ref(),
            couplers: couplers.as_ref(),
            metering,
            backend: backend.to_string(),
        },
    );
    println!();
    println!(
        "  wrote     {} ({}x{})",
        args.output.display(),
        width,
        height
    );
    Ok(())
}

/// `out/` is gitignored, so a fresh clone does not have it. Creating the parent
/// keeps `-o out/foo.png` working without a `mkdir` first.
fn ensure_parent(path: &Path) -> Result<(), CliError> {
    let Some(parent) = path.parent() else {
        return Ok(());
    };
    if parent.as_os_str().is_empty() {
        return Ok(());
    }
    std::fs::create_dir_all(parent).map_err(|source| CliError::CreateDir {
        path: parent.to_path_buf(),
        source,
    })
}
