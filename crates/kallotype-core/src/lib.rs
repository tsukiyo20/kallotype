//! # kallotype-core
//!
//! The reference implementation of the Kallotype film model.
//!
//! Phase 0 is deliberately small: a negative emulsion with a characteristic
//! curve, a development-time dependency, and a paper that the negative is
//! printed onto. Every quantity is in `f64` and in physical units, so that the
//! GPU implementation in `kallotype-gpu` (later) can be checked against it.
//!
//! ## The model
//!
//! ```text
//! linear RGB ──► log10 E ──► negative density ──► print density ──► linear RGB
//!                              (H&D curve,          (paper curve,
//!                               development)         auto-balanced)
//! ```
//!
//! ## What is deliberately *not* here yet
//!
//! - Spectral quantities beyond the exposure step (dye absorption, illuminants).
//! - Colour management: the phase-0 model carries no primaries.
//! - Couplers, grain, halation.
//!
//! Those land in later phases.

#![forbid(unsafe_code)]

pub mod color;
pub mod couplers;
pub mod curve;
pub mod development;
pub mod dye;
pub mod emulsion;
pub mod filters;
mod filters_measured;
pub mod grain;
pub mod halation;
pub mod interimage;
pub mod lut;
mod measured;
pub mod meter;
pub mod model;
pub mod mtf;
pub mod pipeline;
pub mod print;
pub mod psf;
pub mod scan;
pub mod scanner;
pub mod spectral;

pub use color::{linear_to_srgb, srgb_to_linear};
pub use couplers::{Couplers, fit_inhibition};
pub use curve::CharacteristicCurve;
pub use development::DevelopmentParams;
pub use emulsion::{
    FILM_STOCKS, FilmProcess, FilmStock, PAPER_STOCKS, PaperEmulsion, PaperStock, Provenance,
    film_stock, paper_stock,
};
pub use grain::GrainField;
pub use halation::{Halation, Halo};
pub use interimage::InterImage;
pub use lut::ExposureLut;
pub use meter::Metering;
pub use model::{ExposureModel, PrintModel, ScanModel, SpectralModel};
pub use mtf::EmulsionBlur;
pub use pipeline::{
    Finishing, PreparedRender, RenderParams, ScalarModel, render_pixels, render_pixels_finished,
    render_pixels_with_grain,
};
pub use print::{Masking, PrintContext};
pub use scan::ScanContext;
pub use scanner::Scanner;
pub use spectral::{CameraProfile, SpectralContext};
