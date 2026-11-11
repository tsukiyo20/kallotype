//! `kalo` — the command line front end for Kallotype.
//!
//! The binary itself is a three-line wrapper. Everything lives in this crate so
//! that a command can be exercised from a test without spawning a process:
//!
//! ```
//! use clap::Parser;
//! use kallotype_cli::cli::Cli;
//!
//! let cli = Cli::parse_from(["kalo", "stocks"]);
//! kallotype_cli::run(cli).unwrap();
//! ```

#![forbid(unsafe_code)]

pub mod cli;
pub mod commands;
pub mod error;
pub mod filmfile;
pub mod stockfile;

use cli::{Cli, Command};
use error::CliError;

/// Run a parsed command.
///
/// Parsing is separate from execution on purpose: it keeps the argument surface
/// testable and the error type inspectable.
pub fn run(cli: Cli) -> Result<(), CliError> {
    match cli.command {
        Command::Render(args) => commands::render::run(args),
        Command::Contact(args) => commands::contact::run(args),
        Command::Curve(args) => commands::curve::run(args),
        Command::Stocks { json } => {
            commands::stocks::run(json);
            Ok(())
        }
        Command::Stock { command } => match command {
            cli::StockCommand::Check(args) => commands::stock::run(args),
        },
        Command::Bake(args) => commands::bake::run(args),
    }
}
