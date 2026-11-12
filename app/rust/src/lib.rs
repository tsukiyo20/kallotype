//! The app's window onto `kallotype-api`.
//!
//! Everything below this crate is the model; everything above it is the
//! interface. This file is the seam, and it is deliberately thin: a job in, a
//! report out, with progress where a job takes long enough to watch.

pub mod api;
mod frb_generated;
