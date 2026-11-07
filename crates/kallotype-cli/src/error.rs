//! Failures a user can cause, with enough context to fix them.

use std::path::PathBuf;

use kallotype_io::IoError;

/// Everything `kalo` can fail at.
#[derive(Debug)]
pub enum CliError {
    /// The requested stock id is not compiled in.
    UnknownStock {
        /// `"film"` or `"paper"`.
        kind: &'static str,
        /// The id the user typed.
        id: String,
    },
    /// A numeric flag received a value outside its domain.
    InvalidNumber {
        /// The flag, e.g. `"--dev"`.
        flag: &'static str,
        /// The value the user typed.
        value: f64,
        /// What was expected, e.g. `"a positive number of minutes"`.
        expected: &'static str,
    },
    /// The output directory could not be created.
    CreateDir {
        /// The directory that failed.
        path: PathBuf,
        /// The underlying OS error.
        source: std::io::Error,
    },
    /// The input could not be decoded.
    Read {
        /// The file that failed.
        path: PathBuf,
        /// The underlying decoder error.
        source: IoError,
    },
    /// A stock file could not be read, parsed or checked.
    Stock {
        /// The file that failed.
        path: PathBuf,
        /// What the checker said.
        message: String,
    },
    /// The dictionary could not be read.
    Dictionary {
        /// The file that failed.
        path: PathBuf,
        /// What the loader said.
        message: String,
    },
    /// The build has no GPU backend, or the one it has cannot run this render.
    Gpu {
        /// What to tell the user.
        message: String,
    },
    /// A camera sensitivity file could not be read.
    Camera {
        /// The file that failed.
        path: PathBuf,
        /// What went wrong.
        message: String,
    },
    /// A baked table could not be read or written.
    Lut {
        /// The file that failed.
        path: PathBuf,
        /// What the table layer said.
        message: String,
    },
    /// The output could not be encoded.
    Write {
        /// The file that failed.
        path: PathBuf,
        /// The underlying encoder error.
        source: IoError,
    },
}

impl std::fmt::Display for CliError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnknownStock { kind, id } => {
                write!(f, "unknown {kind} stock '{id}' (try `kalo stocks`)")
            }
            Self::InvalidNumber {
                flag,
                value,
                expected,
            } => {
                write!(f, "{flag} must be {expected}, got {value}")
            }
            Self::CreateDir { path, source } => {
                write!(f, "could not create {}: {source}", path.display())
            }
            Self::Read { path, source } => {
                write!(f, "could not read {}: {source}", path.display())
            }
            Self::Dictionary { path, message } => {
                write!(f, "could not read dictionary {}: {message}", path.display())
            }
            Self::Stock { path, message } => {
                write!(f, "stock {}: {message}", path.display())
            }
            Self::Gpu { message } => write!(f, "{message}"),
            Self::Camera { path, message } => {
                write!(f, "camera sensitivity {}: {message}", path.display())
            }
            Self::Lut { path, message } => {
                write!(f, "lookup table {}: {message}", path.display())
            }
            Self::Write { path, source } => {
                write!(f, "could not write {}: {source}", path.display())
            }
        }
    }
}

impl std::error::Error for CliError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::CreateDir { source, .. } => Some(source),
            Self::Read { source, .. } | Self::Write { source, .. } => Some(source),
            Self::UnknownStock { .. }
            | Self::InvalidNumber { .. }
            | Self::Dictionary { .. }
            | Self::Camera { .. }
            | Self::Gpu { .. }
            | Self::Lut { .. }
            | Self::Stock { .. } => None,
        }
    }
}
