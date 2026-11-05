//! Spectral primitives: spectra, sensors, datasets, upsampling and metrics.
//!
//! This crate exists because the film model cannot be honest about colour until
//! it knows what spectrum it started from. An 8-bit RGB pixel is a projection of
//! an unknown spectrum through an unknown sensor; recovering that spectrum is
//! underdetermined, and *how* you recover it is a design decision with measured
//! consequences.
//!
//! The crate therefore ships two things:
//!
//! 1. the plumbing — [`Spectrum`], [`Sensor`], [`ReflectanceSet`];
//! 2. a benchmark harness for comparing candidate reconstructions on the same
//!    data with the same metrics, so the decision can be made from numbers
//!    rather than taste.
//!
//! ```
//! use kallotype_spectral::{Sensor, Spectrum};
//!
//! let grid = Spectrum::uniform(380.0, 10.0, 36).unwrap();
//! let flat = Spectrum::filled(grid.clone(), 0.5);
//! let camera = Sensor::generic_camera(&grid);
//! let response = camera.respond(&flat);
//! assert_eq!(response.len(), 3);
//! ```

#![forbid(unsafe_code)]

pub mod data;
pub mod metrics;
pub mod sensor;
pub mod spectrum;
pub mod upsample;

pub use data::{ReflectanceSet, Sample, load_csv};
pub use metrics::{relative_response_error, rmse, spectral_angle_deg};
pub use sensor::Sensor;
pub use spectrum::{SpectralError, Spectrum};
pub use upsample::{DictionaryUpsampler, PolynomialUpsampler, Upsampler};
