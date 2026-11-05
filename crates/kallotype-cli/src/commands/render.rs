//! `kalo render` — apply the model to a whole image.

use std::path::Path;

use kallotype_core::render_pixels;
use kallotype_io::{load, save};

use crate::cli::RenderArgs;
use crate::commands::common::{print_report, resolve};
use crate::error::CliError;

/// Run the subcommand.
pub fn run(args: RenderArgs) -> Result<(), CliError> {
    let selection = resolve(&args.stock)?;
    let params = selection.render_params(args.ev);
    let prepared = params.prepare();

    let mut image =
        load(&args.input, args.input_encoding.into()).map_err(|source| CliError::Read {
            path: args.input.clone(),
            source,
        })?;
    let (width, height) = (image.width, image.height);

    render_pixels(&mut image.pixels, &prepared);

    ensure_parent(&args.output)?;

    save(&args.output, &image).map_err(|source| CliError::Write {
        path: args.output.clone(),
        source,
    })?;

    print_report(&params, width, height);
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
