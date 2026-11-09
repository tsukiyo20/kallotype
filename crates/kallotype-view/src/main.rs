//! `kaloview` — write the strip the app draws.
//!
//! ```text
//! kaloview <stock> <output.json> [minutes...]
//! ```

use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;

use kallotype_view::{StripSpec, strip_for};

const USAGE: &str = "\
usage: kaloview <stock> <output.json> [minutes...]

Writes the strip the interface draws, as JSON. Every frame holds the same
exposures; only the development time differs.
";

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    let Some(stock) = args.first() else {
        eprint!("{USAGE}");
        return ExitCode::from(2);
    };
    let Some(output) = args.get(1) else {
        eprint!("{USAGE}");
        return ExitCode::from(2);
    };

    let mut spec = StripSpec::default();
    if args.len() > 2 {
        let mut minutes = Vec::new();
        for raw in &args[2..] {
            match raw.parse::<f64>() {
                Ok(time) if time.is_finite() && time > 0.0 => minutes.push(time),
                _ => {
                    eprintln!("kaloview: not a development time: {raw}");
                    return ExitCode::from(2);
                }
            }
        }
        spec.minutes = minutes;
    }

    let Some(strip) = strip_for(stock.as_str(), &spec) else {
        eprintln!("kaloview: no film called {stock}");
        return ExitCode::from(1);
    };

    let json = match serde_json::to_string_pretty(&strip) {
        Ok(json) => json,
        Err(error) => {
            eprintln!("kaloview: {error}");
            return ExitCode::from(1);
        }
    };

    let path = PathBuf::from(output);
    if let Some(parent) = path.parent()
        && !parent.as_os_str().is_empty()
        && let Err(error) = fs::create_dir_all(parent)
    {
        eprintln!("kaloview: {}: {error}", parent.display());
        return ExitCode::from(1);
    }
    if let Err(error) = fs::write(&path, format!("{json}\n")) {
        eprintln!("kaloview: {}: {error}", path.display());
        return ExitCode::from(1);
    }

    let patches = strip.frames.first().map_or(0, |frame| frame.patches.len());
    println!(
        "  wrote     {} ({} frames, {} patches each)",
        path.display(),
        strip.frames.len(),
        patches
    );
    ExitCode::SUCCESS
}
