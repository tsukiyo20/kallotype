//! `kalo curve` — say what a development does, without rendering anything.

use crate::cli::CurveArgs;
use crate::commands::common::{print_report, resolve};
use crate::error::CliError;

/// Run the subcommand.
pub fn run(args: CurveArgs) -> Result<(), CliError> {
    let selection = resolve(&args.stock)?;
    let params = selection.render_params(0.0);
    let prepared = selection.prepare(0.0)?;

    print_report(&params, &prepared, 0, 0);

    if args.sweep {
        println!();
        println!("  exposure   R density   G density   B density");
        for stops in [-2.0_f64, -1.0, 0.0, 1.0, 2.0] {
            let log_e = 0.18_f64.log10() + stops * 2.0_f64.log10();
            let densities = prepared.channels().map(|channel| channel.density(log_e));
            println!(
                "  {:>+5.1} EV   {:>9.3}   {:>9.3}   {:>9.3}",
                stops, densities[0], densities[1], densities[2]
            );
        }
    }

    Ok(())
}
