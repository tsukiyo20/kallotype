//! `kalo render` — apply the model to a whole image.

use std::path::Path;

use kallotype_core::{Finishing, GrainField, Halation, render_pixels_finished};
use kallotype_io::{load, save};

use crate::cli::RenderArgs;
use crate::commands::common::{print_report, resolve};
use crate::error::CliError;

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
    let finishing = Finishing {
        halation: halation.as_ref(),
        grain: grain.as_ref(),
    };
    render_pixels_finished(
        &mut image.pixels,
        &prepared,
        width as usize,
        height as usize,
        &finishing,
    );

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
        grain.as_ref(),
        halation.as_ref(),
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
