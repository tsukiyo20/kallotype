//! `kalo stock check` — is this stock file what it says it is?

use std::path::PathBuf;

use crate::cli::StockCheckArgs;
use crate::error::CliError;
use crate::stockfile::{StockFile, Verdict};

/// Check a stock file and report.
///
/// # Errors
///
/// Fails if the file cannot be read or parsed, or if any check fails.
pub fn run(args: StockCheckArgs) -> Result<(), CliError> {
    let file = StockFile::read(&args.file).map_err(|error| CliError::Stock {
        path: args.file.clone(),
        message: error.to_string(),
    })?;

    println!("{}", file.path().display());
    let kind = if file.is_film() { "film" } else { "paper" };
    println!("  {} ({kind})", file.label());

    let findings = file.check();
    for finding in &findings {
        println!("{finding}");
    }

    let failures = findings
        .iter()
        .filter(|f| f.verdict == Verdict::Fail)
        .count();
    if failures > 0 {
        return Err(CliError::Stock {
            path: PathBuf::from(file.path()),
            message: format!("{failures} check(s) failed"),
        });
    }
    println!("\n  usable.");
    Ok(())
}
