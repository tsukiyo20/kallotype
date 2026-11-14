//! The use case, apart from the interface that asked for it.
//!
//! `kallotype-core` is the model; this crate is what you do with it. A
//! photograph is read once, metered, developed at a time and printed on a
//! paper; a contact proof is the same photograph exposed once through a ladder
//! of times; a roll is both, from one decode. All of it was written inside
//! `kalo` first, where the only way to reach it was a command line. It lives
//! here now because the app reaches the same work through a function call, and
//! two implementations of "develop a roll" would be one too many.
//!
//! The entry points are [`render()`], [`contact()`] and [`roll()`]. The first
//! two take a decoded image; the third reads the photograph itself, because a
//! roll is exactly the case where reading it once matters. A bench session
//! ([`PreviewSession`]) is the same idea for a window: read the photograph once,
//! then print as many previews of it as the person drags past.

pub mod catalogue;
pub mod chart;
pub mod contact;
pub mod error;
pub mod input;
pub mod preview;
pub mod render;
pub mod roll;
pub mod selection;

pub use chart::{
    FilmCurve, FrameChart, PaperChart, PrintChart, PrintChartOptions, chart, chart_for, film_curve,
    paper_chart, print_chart, print_chart_with,
};
pub use contact::{ContactOptions, ContactOutcome, contact, ladder};
pub use error::Error;
pub use input::read_input;
pub use preview::{PreviewFrame, PreviewRequest, PreviewSession};
pub use render::{
    Backend, Exposure, OwnedFinishing, RenderOptions, RenderOutcome, render, render_image,
};
pub use roll::{Progress, RollOutcome, RollRequest, roll};
pub use selection::{Selection, StockChoice, camera_profile, check_model, resolve};
