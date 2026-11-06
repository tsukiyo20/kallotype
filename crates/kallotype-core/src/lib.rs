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
//! Those land in later phases; see `docs/0001-architecture.md` and `ROADMAP.md`.

#![forbid(unsafe_code)]

pub mod color;
pub mod curve;
pub mod development;
pub mod emulsion;
pub mod lut;
pub mod pipeline;
pub mod print;
pub mod scan;
pub mod spectral;

pub use color::{linear_to_srgb, srgb_to_linear};
pub use curve::CharacteristicCurve;
pub use development::DevelopmentParams;
pub use emulsion::{FILM_STOCKS, FilmStock, PAPER_STOCKS, PaperStock, film_stock, paper_stock};
pub use lut::ExposureLut;
pub use pipeline::{PreparedRender, RenderParams, render_pixels};
pub use print::PrintContext;
pub use scan::ScanContext;
pub use spectral::{CameraProfile, SpectralContext};
