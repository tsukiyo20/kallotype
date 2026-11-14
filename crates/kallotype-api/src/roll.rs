//! A roll: one photograph, one decode, five developments and a proof.
//!
//! The bench used to ask the model six times — five prints and a proof — and
//! each of those calls decoded the photograph again. It was the largest single
//! cost of making a roll, and it bought nothing: the negative is the same
//! negative at every development time. This module is that knowledge in one
//! place: read the file once, develop it five ways, print the proof, write the
//! lot.

use std::path::PathBuf;

use kallotype_core::FilmStock;
use kallotype_io::resize_to_width;

use crate::contact::{ContactOptions, ContactOutcome, contact};
use crate::error::Error;
use crate::input::read_input;
use crate::render::{Exposure, RenderOptions, RenderOutcome, render};
use crate::selection::Selection;

/// What a roll is asked for.
#[derive(Debug, Clone)]
pub struct RollRequest {
    /// The photograph.
    pub input: PathBuf,
    /// How to read an ordinary image (a raw carries its own encoding).
    pub input_encoding: kallotype_io::InputEncoding,
    /// One output per development, in the ladder's order.
    pub frames: Vec<PathBuf>,
    /// Where the proof goes, if one is wanted.
    pub contact: Option<PathBuf>,
    /// Where its hit-testing record goes.
    pub record: Option<PathBuf>,
    /// The development times, in minutes.
    pub times: Vec<f64>,
    /// The width the bench shows the frames at.
    pub size: u32,
    /// The proof's resolution.
    pub dpi: f64,
    /// Exposure offset, or metering.
    pub ev: Exposure,
    /// Extra print exposure in stops.
    pub print_ev: f64,
    /// Width of the film frame the image represents, in millimetres.
    pub frame_mm: f64,
    /// Add grain.
    pub grain: bool,
    /// Override the grain's correlation length.
    pub grain_um: Option<f64>,
    /// Grain seed.
    pub grain_seed: u64,
    /// Add halation.
    pub halation: bool,
    /// Add DIR couplers.
    pub couplers: bool,
    /// Render on the GPU when there is one.
    pub gpu: bool,
}

impl Default for RollRequest {
    fn default() -> Self {
        Self {
            input: PathBuf::new(),
            input_encoding: kallotype_io::InputEncoding::Srgb,
            frames: Vec::new(),
            contact: None,
            record: None,
            times: Vec::new(),
            size: 1200,
            dpi: 600.0,
            ev: Exposure::Auto,
            print_ev: 0.0,
            frame_mm: 36.0,
            grain: true,
            grain_um: None,
            grain_seed: 0,
            halation: true,
            couplers: true,
            gpu: true,
        }
    }
}

/// Where a roll has got to.
#[derive(Debug, Clone, Copy)]
pub enum Progress {
    /// A frame has been developed and written.
    Frame {
        /// How many are done, one-based.
        index: usize,
        /// How many there are.
        total: usize,
    },
    /// The proof has been printed and written.
    Contact,
    /// Everything is written.
    Done,
}

/// What a roll produced.
pub struct RollOutcome {
    /// One outcome per frame, in the ladder's order.
    pub frames: Vec<RenderOutcome>,
    /// The proof, if one was asked for.
    pub contact: Option<ContactOutcome>,
    /// The chart: the same wedge through every development, for the interface.
    pub chart: Vec<crate::chart::FrameChart>,
    /// The size of the photograph as it was read.
    pub source: (u32, u32),
}

/// Develop a photograph into a roll: one read, five prints, one proof.
///
/// `film` overrides the stock the selection resolved to, for a `.kalofilm`
/// file. `progress` is called as each piece lands, so an interface can show the
/// bench filling up without polling the file system.
pub fn roll(
    request: &RollRequest,
    selection: &Selection,
    film: Option<&'static FilmStock>,
    progress: &mut dyn FnMut(Progress),
) -> Result<RollOutcome, Error> {
    if request.frames.len() != request.times.len() {
        return Err(Error::Contact {
            message: format!(
                "{} development times but {} output frames",
                request.times.len(),
                request.frames.len()
            ),
        });
    }
    if request.size == 0 {
        return Err(Error::InvalidNumber {
            flag: "--size",
            value: f64::from(request.size),
            expected: "a positive width in pixels",
        });
    }
    if let Some(bad) = request
        .times
        .iter()
        .copied()
        .find(|time| !(time.is_finite() && *time > 0.0))
    {
        return Err(Error::InvalidNumber {
            flag: "--dev",
            value: bad,
            expected: "a positive number of minutes",
        });
    }

    let source = read_input(&request.input, request.input_encoding)?;
    let source_size = (source.width, source.height);
    // The bench is one size for every frame; the proof is sampled from the
    // photograph itself, at the frame the film carries.
    let bench = resize_to_width(&source, request.size);

    let options = RenderOptions {
        ev: request.ev,
        print_ev: request.print_ev,
        frame_mm: request.frame_mm,
        grain: request.grain,
        grain_um: request.grain_um,
        grain_seed: request.grain_seed,
        halation: request.halation,
        couplers: request.couplers,
        gpu: request.gpu,
        ..RenderOptions::default()
    };

    let total = request.times.len();
    let mut frames = Vec::with_capacity(total);
    for (index, output) in request.frames.iter().enumerate() {
        // The render turns the pixels into a print in place, so every frame
        // starts from the bench again — and it is a copy of the same decode,
        // not another one. The selection is copied too, because the only thing
        // that changes between the frames is the development time.
        let mut image = bench.clone();
        let mut frame_selection = selection.clone();
        frame_selection.development.time_min = request.times[index];
        let outcome = render(&mut image, film, &frame_selection, &options, output)?;
        frames.push(outcome);
        progress(Progress::Frame {
            index: index + 1,
            total,
        });
    }

    let proof = if request.contact.is_some() || request.record.is_some() {
        let sheet = request.contact.clone().unwrap_or_else(|| {
            let mut path = request.input.clone();
            path.set_extension("contact.png");
            path
        });
        let options = ContactOptions {
            ev: request.ev,
            print_ev: request.print_ev,
            dpi: request.dpi,
            grain: request.grain,
            halation: request.halation,
            couplers: request.couplers,
            edge_codes: true,
            record: request.record.clone(),
        };
        let outcome = contact(&source, film, selection, &request.times, &options, &sheet)?;
        progress(Progress::Contact);
        Some(outcome)
    } else {
        None
    };

    // The chart is the stock and the development, not the photograph: it is
    // the same wedge the committed strip was drawn from, so a roll the app
    // developed can be read against the one it ships with.
    let chart = crate::chart::chart(
        film.unwrap_or(selection.film),
        &request.times,
        selection.development.temp_c,
    );

    progress(Progress::Done);
    Ok(RollOutcome {
        frames,
        contact: proof,
        chart,
        source: source_size,
    })
}
