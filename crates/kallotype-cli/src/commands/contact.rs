//! `kalo contact` — the proof: one exposure, the whole ladder.

use kallotype_api::{ContactOptions, StockChoice, contact, ladder};
use kallotype_core::Metering;
use kallotype_core::contact::SheetGeometry;

use crate::cli::ContactArgs;
use crate::commands::common::{read_input, resolve_stock_choice};
use crate::error::CliError;

/// Run the subcommand.
pub fn run(args: ContactArgs) -> Result<(), CliError> {
    // A proof is one photograph through a ladder of times, so only the stock
    // and the temperature are chosen here; each strip's development is its own.
    let choice = StockChoice {
        film: args.film.clone(),
        paper: args.paper.clone(),
        temp: args.temp,
        spectral: args.spectral,
        ..StockChoice::default()
    };
    let selection = resolve_stock_choice(&choice)?;
    let label = selection.film.label;

    let times: Vec<f64> = if args.dev.is_empty() {
        ladder().to_vec()
    } else {
        args.dev.clone()
    };

    let source = read_input(&args.input, args.input_encoding.into())?;
    let options = ContactOptions {
        ev: args.ev.into(),
        print_ev: args.print_ev,
        dpi: args.dpi,
        grain: args.grain,
        halation: args.halation,
        couplers: args.couplers,
        edge_codes: !args.no_edge_codes,
        record: args.record.clone(),
    };
    let outcome = contact(&source, None, &selection, &times, &options, &args.output)?;

    report(
        &outcome.geometry,
        &args,
        &times,
        label,
        selection.development.temp_c,
        outcome.exposure_ev,
        outcome.metering,
    );
    Ok(())
}

fn report(
    sheet: &SheetGeometry,
    args: &ContactArgs,
    times: &[f64],
    film: &str,
    temp: f64,
    exposure_ev: f64,
    metering: Option<Metering>,
) {
    let measured = sheet.frames.len();
    let listed = times
        .iter()
        .map(|minutes| format!("{minutes:.1}"))
        .collect::<Vec<_>>()
        .join(", ");
    println!("  film      {film}");
    println!(
        "  paper     {}",
        kallotype_core::paper_stock(&args.paper)
            .expect("resolved above")
            .label
    );
    println!("  strips    {measured} at {temp:.1} °C — {listed} min");
    match metering {
        Some(metering) => println!(
            "  exposure  auto: {:+.2} EV (mean luminance {:.3})",
            metering.ev, metering.key
        ),
        None => println!("  exposure  {:+.2} EV", exposure_ev),
    }
    let mm = |pixels: usize| pixels as f64 * 25.4 / sheet.dpi;
    println!(
        "  sheet     {}x{} px at {:.0} dpi ({:.0}x{:.0} mm)",
        sheet.width,
        sheet.height,
        sheet.dpi,
        mm(sheet.width),
        mm(sheet.height)
    );
    println!();
    println!(
        "  wrote     {} ({}x{})",
        args.output.display(),
        sheet.width,
        sheet.height
    );
}
