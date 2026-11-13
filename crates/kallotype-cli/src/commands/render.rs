//! `kalo render` — apply the model to a whole image.

use kallotype_api::{RenderOptions, render};
use kallotype_io::resize_to_width;

use crate::cli::RenderArgs;
use crate::commands::common::{Rendering, print_report, read_input, resolve};
use crate::error::CliError;

/// Run the subcommand.
pub fn run(args: RenderArgs) -> Result<(), CliError> {
    let selection = resolve(&args.stock)?;
    // A film can arrive as a file. It is loaded before the image is, because
    // the film is an input to the model rather than a pass over its output.
    let film = match &args.stock.film_file {
        Some(path) => Some(crate::filmfile::read(path).map_err(|error| CliError::Film {
            path: path.clone(),
            message: error.to_string(),
        })?),
        None => None,
    };

    let mut image = read_input(&args.input, args.input_encoding.into())?;
    // Downsampled before anything else, because everything after this reads the
    // frame at the size it is rendered at: the meter averages it, the grain is
    // scaled by it, and the emulsions blur across it.
    if let Some(size) = args.size {
        image = resize_to_width(&image, size);
    }

    let options = RenderOptions {
        ev: args.ev.into(),
        print_ev: args.print_ev,
        balance_from: args.balance_from,
        frame_mm: args.frame_mm,
        emulsion: !args.no_emulsion,
        halation: args.halation,
        couplers: args.couplers,
        interimage: args.interimage,
        grain: args.grain,
        grain_um: args.grain_um,
        grain_seed: args.grain_seed,
        scanner: args.scanner,
        scan_optics_um: args.scan_optics_um,
        gpu: args.gpu,
    };
    let outcome = render(&mut image, film, &selection, &options, &args.output)?;
    for warning in &outcome.warnings {
        eprintln!("warning: {warning}");
    }

    print_report(
        &outcome.params,
        &outcome.prepared,
        outcome.width,
        outcome.height,
        &Rendering {
            grain: outcome.finishing.grain.as_ref(),
            emulsion: outcome.finishing.emulsion.as_ref(),
            halation: outcome.finishing.halation.as_ref(),
            couplers: outcome.finishing.couplers.as_ref(),
            interimage: outcome.finishing.interimage.as_ref(),
            scanner: outcome.scanner.as_ref(),
            metering: outcome.metering,
            backend: outcome.backend.to_string(),
        },
    );
    println!();
    println!(
        "  wrote     {} ({}x{})",
        args.output.display(),
        outcome.width,
        outcome.height
    );
    Ok(())
}
