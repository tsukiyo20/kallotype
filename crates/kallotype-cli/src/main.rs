//! The `kalo` binary: parse, run, report, exit.

use std::process::ExitCode;

use clap::Parser;
use kallotype_cli::cli::Cli;

fn main() -> ExitCode {
    match kallotype_cli::run(Cli::parse()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("error: {error}");

            // Print the chain as well: the outer message says what failed, the
            // source says why.
            let mut source = std::error::Error::source(&error);
            while let Some(cause) = source {
                eprintln!("  caused by: {cause}");
                source = cause.source();
            }

            ExitCode::FAILURE
        }
    }
}
