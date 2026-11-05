//! Loading reflectance datasets from tidy CSV.
//!
//! The format is deliberately boring so that any spectral library can be
//! converted into it with ten lines of script:
//!
//! ```text
//! wavelength,A,B,N5,foli
//! 380,0.066,0.189,0.105,0.051
//! 390,...
//! ```
//!
//! One column per sample, first column the wavelength. Lines starting with `#`
//! are comments.

use std::fmt;
use std::path::{Path, PathBuf};

use crate::spectrum::{SpectralError, Spectrum};

/// A single measured material.
#[derive(Debug, Clone)]
pub struct Sample {
    /// Column heading from the CSV.
    pub name: String,
    /// The reflectance spectrum, dimensionless in `[0, 1]`.
    pub reflectance: Spectrum,
}

/// A named collection of reflectance spectra on a common grid.
#[derive(Debug, Clone)]
pub struct ReflectanceSet {
    /// Dataset name, taken from the file stem.
    pub name: String,
    /// The shared wavelength grid.
    pub grid: Spectrum,
    /// One entry per column.
    pub samples: Vec<Sample>,
}

impl ReflectanceSet {
    /// Number of samples.
    #[must_use]
    pub fn len(&self) -> usize {
        self.samples.len()
    }

    /// Whether the set is empty. The loader rejects empty datasets, so this is
    /// always `false` in practice.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.samples.is_empty()
    }

    /// Look a sample up by name.
    #[must_use]
    pub fn sample(&self, name: &str) -> Option<&Sample> {
        self.samples.iter().find(|sample| sample.name == name)
    }
}

/// A dataset could not be read.
#[derive(Debug)]
pub enum DataError {
    /// The file could not be opened or read.
    Io {
        /// The file that failed.
        path: PathBuf,
        /// The underlying OS error.
        source: std::io::Error,
    },
    /// A row or header did not have the expected shape.
    Format {
        /// 1-based line number.
        line: usize,
        /// What was wrong.
        message: String,
    },
    /// The values could not be turned into spectra.
    Spectral(SpectralError),
    /// The file had a header but no data rows.
    NoSamples,
}

impl fmt::Display for DataError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io { path, source } => write!(f, "could not read {}: {source}", path.display()),
            Self::Format { line, message } => write!(f, "line {line}: {message}"),
            Self::Spectral(error) => write!(f, "{error}"),
            Self::NoSamples => write!(f, "the dataset has a header but no samples"),
        }
    }
}

impl std::error::Error for DataError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io { source, .. } => Some(source),
            Self::Spectral(error) => Some(error),
            Self::Format { .. } | Self::NoSamples => None,
        }
    }
}

impl From<SpectralError> for DataError {
    fn from(error: SpectralError) -> Self {
        Self::Spectral(error)
    }
}

/// Read a tidy CSV of reflectance spectra.
///
/// # Errors
///
/// Fails if the file cannot be read, if a row is ragged, or if the resulting
/// grid is invalid.
pub fn load_csv(path: impl AsRef<Path>) -> Result<ReflectanceSet, DataError> {
    let path = path.as_ref();
    let text = std::fs::read_to_string(path).map_err(|source| DataError::Io {
        path: path.to_path_buf(),
        source,
    })?;
    parse_csv(&text, dataset_name(path))
}

fn dataset_name(path: &Path) -> String {
    path.parent()
        .and_then(Path::file_name)
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| "dataset".to_owned())
}

/// Parse the CSV body. Split out from [`load_csv`] so it can be tested without
/// touching the filesystem.
///
/// # Errors
///
/// See [`load_csv`].
pub fn parse_csv(text: &str, name: String) -> Result<ReflectanceSet, DataError> {
    let mut header: Option<Vec<String>> = None;
    let mut wavelengths: Vec<f64> = Vec::new();
    let mut columns: Vec<Vec<f64>> = Vec::new();

    for (index, raw) in text.lines().enumerate() {
        let line_number = index + 1;
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }

        let cells: Vec<&str> = line.split(',').map(str::trim).collect();
        match &header {
            None => {
                if cells.first() != Some(&"wavelength") {
                    return Err(DataError::Format {
                        line: line_number,
                        message: "the first column must be named `wavelength`".to_owned(),
                    });
                }
                if cells.len() < 2 {
                    return Err(DataError::Format {
                        line: line_number,
                        message: "the header needs at least one sample column".to_owned(),
                    });
                }
                columns = vec![Vec::new(); cells.len() - 1];
                header = Some(cells[1..].iter().map(|cell| (*cell).to_owned()).collect());
            }
            Some(names) => {
                if cells.len() != names.len() + 1 {
                    return Err(DataError::Format {
                        line: line_number,
                        message: format!(
                            "expected {} cells (wavelength + {} samples), found {}",
                            names.len() + 1,
                            names.len(),
                            cells.len()
                        ),
                    });
                }
                let parse = |cell: &str| -> Result<f64, DataError> {
                    cell.parse::<f64>().map_err(|_| DataError::Format {
                        line: line_number,
                        message: format!("`{cell}` is not a number"),
                    })
                };
                wavelengths.push(parse(cells[0])?);
                for (column, cell) in columns.iter_mut().zip(&cells[1..]) {
                    column.push(parse(cell)?);
                }
            }
        }
    }

    let names = header.ok_or(DataError::NoSamples)?;
    if wavelengths.is_empty() {
        return Err(DataError::NoSamples);
    }

    let step = if wavelengths.len() > 1 {
        wavelengths[1] - wavelengths[0]
    } else {
        1.0
    };
    for pair in wavelengths.windows(2) {
        if (pair[1] - pair[0] - step).abs() > 1e-6 {
            return Err(DataError::Format {
                line: 0,
                message: "the wavelength column must be uniformly spaced".to_owned(),
            });
        }
    }
    // The grid carries the wavelength axis only; its values are placeholders.
    let count = wavelengths.len();
    let grid = Spectrum::new(wavelengths[0], step, vec![0.0; count])?;

    let samples = names
        .into_iter()
        .zip(columns)
        .map(|(name, values)| {
            Ok(Sample {
                name,
                reflectance: Spectrum::new(grid.start_nm(), grid.step_nm(), values)?,
            })
        })
        .collect::<Result<Vec<_>, SpectralError>>()?;

    Ok(ReflectanceSet {
        name,
        grid,
        samples,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const BODY: &str = "\
# a comment
wavelength,A,B
380,0.1,0.2
390,0.3,0.4
";

    #[test]
    fn parses_a_minimal_table() {
        let set = parse_csv(BODY, "test".to_owned()).unwrap();
        assert_eq!(set.len(), 2);
        assert_eq!(set.grid.len(), 2);
        assert!((set.sample("B").unwrap().reflectance.values()[1] - 0.4).abs() < 1e-12);
    }

    #[test]
    fn rejects_a_ragged_row() {
        let body = "wavelength,A,B\n380,0.1\n";
        assert!(matches!(
            parse_csv(body, "test".to_owned()),
            Err(DataError::Format { line: 2, .. })
        ));
    }

    #[test]
    fn rejects_a_header_without_samples() {
        assert!(parse_csv("wavelength\n", "test".to_owned()).is_err());
    }
}
