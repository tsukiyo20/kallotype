//! `kalo render` — apply the model to a whole image.

use std::path::Path;

use kallotype_core::{Couplers, Finishing, GrainField, Halation, render_pixels_finished};
use kallotype_io::{load, save};

use crate::cli::RenderArgs;
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
/// The fallback is deliberate and loud. A user who passes `--gpu` on a machine
/// with no adapter, or with a spectral render the backend does not implement,
/// gets a warning and a correct image, not an error and not a silently different
/// one.
#[cfg(feature = "gpu")]
fn render_pixels(
    pixels: &mut [[f64; 3]],
    prepared: &kallotype_core::PreparedRender,
    width: usize,
    height: usize,
    finishing: &Finishing,
    on_gpu: bool,
) -> Result<Backend, CliError> {
    if on_gpu {
        let effects = finishing.halation.is_some()
            || finishing.grain.is_some()
            || finishing.couplers.is_some();
        match kallotype_gpu::Gpu::new() {
            Ok(gpu) if !effects && prepared.scalar_model().is_some() => {
                let rendered = gpu
                    .render(pixels, prepared)
                    .map_err(|error| CliError::Gpu {
                        message: error.to_string(),
                    })?;
                pixels.copy_from_slice(&rendered);
                return Ok(Backend::Gpu(gpu.describe()));
            }
            Ok(_) if effects => {
                eprintln!(
                    "warning: --gpu does not implement grain, halation or couplers yet; \
                     rendering on the cpu"
                );
                return Ok(render_on_cpu(pixels, prepared, width, height, finishing));
            }
            Ok(_) => {
                eprintln!(
                    "warning: --gpu implements the scalar path only; this render is spectral, \
                     so it is running on the cpu"
                );
                return Ok(render_on_cpu(pixels, prepared, width, height, finishing));
            }
            Err(error) => {
                eprintln!("warning: {error}; rendering on the cpu");
            }
        }
    }
    Ok(render_on_cpu(pixels, prepared, width, height, finishing))
}

/// Without the feature the flag still exists, so the answer is a sentence rather
/// than clap's "unexpected argument".
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
        return Err(CliError::Gpu {
            message: "this build has no GPU backend: \
                      `cargo install kallotype-cli --features gpu`"
                .to_owned(),
        });
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

/// Run the subcommand.
pub fn run(args: RenderArgs) -> Result<(), CliError> {
    let selection = resolve(&args.stock)?;
    let params = selection.render_params(args.ev);
    let prepared = selection.prepare(args.ev)?;

    let mut image =
        load(&args.input, args.input_encoding.into()).map_err(|source| CliError::Read {
            path: args.input.clone(),
            source,
        })?;
    let (width, height) = (image.width, image.height);

    let pixel_um = args.frame_mm * 1000.0 / width.max(1) as f64;
    let grain = args.grain.then(|| {
        GrainField::new(
            width as usize,
            height as usize,
            args.frame_mm,
            args.grain_seed,
        )
    });
    let halation = args.halation.then(|| Halation::typical(pixel_um));
    let couplers = args.couplers.then(|| Couplers::typical(pixel_um));
    let finishing = Finishing {
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
            halation: halation.as_ref(),
            couplers: couplers.as_ref(),
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
