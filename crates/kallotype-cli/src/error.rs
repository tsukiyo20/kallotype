//! Failures a user can cause, with enough context to fix them.
//!
//! The variants live in `kallotype-api`, because the app reaches the same
//! failures through the same functions. The name here is the CLI's; the type is
//! the model's.

pub use kallotype_api::Error as CliError;
