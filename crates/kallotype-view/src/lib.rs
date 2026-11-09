//! Where the model becomes something you can look at.
//!
//! `kallotype-core` answers what one exposure does to one emulsion. This crate
//! arranges those answers into the shape an interface draws: a strip of frames
//! holding the *same* exposures, each developed for a different length of time,
//! so that the only thing that differs between them is how long they were in the
//! developer.
//!
//! It draws nothing, owns no window and reads no image. A patch is numbers; what
//! a density looks like is the frontend's business.
//!
//! ```text
//! FilmStock + StripSpec ──► Strip ──► JSON ──► the app
//! ```
//!
//! The JSON is written by the `kaloview` binary and committed as an app asset,
//! so that building the interface does not need a Rust toolchain. That asset is
//! a rendering of the model at a commit, not a second model: regenerate it with
//! `just view`, never by hand.

#![forbid(unsafe_code)]

use kallotype_core::{DevelopmentParams, FilmStock, film_stock};
use serde::Serialize;

/// The exposures a strip is drawn from, and how long each frame was developed.
#[derive(Debug, Clone, PartialEq)]
pub struct StripSpec {
    /// Development times in minutes, one frame each.
    pub minutes: Vec<f64>,
    /// The developer's temperature in °C, shared by every frame.
    pub temp_c: f64,
    /// How many patches each frame holds; at least one.
    pub patches: usize,
    /// The dimmest patch's log10 exposure.
    pub log_e_min: f64,
    /// The brightest patch's log10 exposure.
    pub log_e_max: f64,
}

impl Default for StripSpec {
    /// A five-frame bracket around a reference development, nine patches across
    /// two and a bit decades of exposure, at 20 °C.
    fn default() -> Self {
        Self {
            minutes: vec![3.0, 6.0, 9.0, 12.0, 15.0],
            temp_c: 20.0,
            patches: 9,
            log_e_min: -2.0,
            log_e_max: 0.8,
        }
    }
}

/// One exposure, and what the developed emulsion did with it.
#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
pub struct Patch {
    /// The log10 exposure this patch received, on the scale where a white card
    /// is 1.0 and mid grey is `log10(0.18)`.
    pub log_e: f64,
    /// Dye density in the red, green and blue records, before the negative's
    /// own base, fog and mask are counted in.
    pub dye_density: [f64; 3],
}

/// One frame: the same exposures as every other frame, developed once.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Frame {
    /// How long this frame was in the developer, in minutes.
    pub minutes: f64,
    /// The developer's temperature in °C.
    pub temp_c: f64,
    /// Contrast in each record, after development.
    pub gamma: [f64; 3],
    /// The dye's density floor, after fog.
    pub d_min: [f64; 3],
    /// The dye's density ceiling.
    pub d_max: [f64; 3],
    /// The wedge, dimmest exposure first.
    pub patches: Vec<Patch>,
}

/// One stock, one temperature, and a bracket of development times.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Strip {
    /// The stock's id, as the CLI and the `.kalofilm` files spell it.
    pub stock_id: String,
    /// The stock's label.
    pub label: String,
    /// The stock's note: what was measured, and what was borrowed.
    pub note: String,
    /// Base, fog and the orange mask, in status density. A densitometer reads
    /// this on top of [`Patch::dye_density`].
    pub base_density: [f64; 3],
    /// The stock's reference development, in minutes.
    pub reference_time_min: f64,
    /// The stock's reference temperature, in °C.
    pub reference_temp_c: f64,
    /// The frames, in the order the spec gave them.
    pub frames: Vec<Frame>,
}

/// Arrange one stock into a strip.
///
/// Every frame is developed from the stock's own reference, so `minutes` is an
/// absolute time and not an offset from anything this program invented.
#[must_use]
pub fn strip(stock: &FilmStock, spec: &StripSpec) -> Strip {
    let patches = spec.patches.max(1);
    let span = spec.log_e_max - spec.log_e_min;
    let log_e_at = |index: usize| -> f64 {
        if patches == 1 {
            spec.log_e_min
        } else {
            spec.log_e_min + span * (index as f64 / (patches - 1) as f64)
        }
    };

    let frames = spec
        .minutes
        .iter()
        .map(|&minutes| {
            let development = DevelopmentParams {
                time_min: minutes,
                temp_c: spec.temp_c,
                reference_time_min: stock.reference_time_min,
                reference_temp_c: stock.reference_temp_c,
                ..DevelopmentParams::default()
            };
            let curves = stock.channels.map(|channel| development.apply_to(channel));

            Frame {
                minutes,
                temp_c: spec.temp_c,
                gamma: curves.map(|curve| curve.gamma),
                d_min: curves.map(|curve| curve.d_min),
                d_max: curves.map(|curve| curve.d_max),
                patches: (0..patches)
                    .map(|index| {
                        let log_e = log_e_at(index);
                        Patch {
                            log_e,
                            dye_density: curves.map(|curve| curve.density(log_e)),
                        }
                    })
                    .collect(),
            }
        })
        .collect();

    Strip {
        stock_id: stock.id.to_owned(),
        label: stock.label.to_owned(),
        note: stock.note.to_owned(),
        base_density: stock.base_density,
        reference_time_min: stock.reference_time_min,
        reference_temp_c: stock.reference_temp_c,
        frames,
    }
}

/// Arrange a stock by id, or `None` when there is no such stock.
#[must_use]
pub fn strip_for(id: &str, spec: &StripSpec) -> Option<Strip> {
    film_stock(id).map(|stock| strip(stock, spec))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn a_strip() -> Strip {
        strip_for("vision3_500t", &StripSpec::default()).expect("the default stock exists")
    }

    #[test]
    fn every_frame_holds_the_same_exposures() {
        let strip = a_strip();
        let first: Vec<f64> = strip.frames[0]
            .patches
            .iter()
            .map(|patch| patch.log_e)
            .collect();
        for frame in &strip.frames {
            let exposures: Vec<f64> = frame.patches.iter().map(|patch| patch.log_e).collect();
            assert_eq!(exposures, first, "a frame, {} min", frame.minutes);
        }
    }

    #[test]
    fn the_strip_is_asked_for_as_many_patches_as_it_holds() {
        let strip = a_strip();
        for frame in &strip.frames {
            assert_eq!(frame.patches.len(), StripSpec::default().patches);
        }
    }

    #[test]
    fn density_rises_with_exposure() {
        let strip = a_strip();
        for frame in &strip.frames {
            for channel in 0..3 {
                let densities: Vec<f64> = frame
                    .patches
                    .iter()
                    .map(|patch| patch.dye_density[channel])
                    .collect();
                assert!(
                    densities.windows(2).all(|pair| pair[1] >= pair[0]),
                    "channel {channel} at {} min: {densities:?}",
                    frame.minutes
                );
            }
        }
    }

    #[test]
    fn longer_development_builds_contrast() {
        let strip = a_strip();
        let first = strip.frames.first().expect("frames");
        let last = strip.frames.last().expect("frames");
        for channel in 0..3 {
            assert!(
                last.gamma[channel] > first.gamma[channel],
                "channel {channel}: {} then {}",
                first.gamma[channel],
                last.gamma[channel]
            );
        }
    }

    #[test]
    fn the_reference_development_is_the_stock_default() {
        let stock = film_stock("ilford_delta400").expect("delta 400 exists");
        let spec = StripSpec {
            minutes: vec![stock.reference_time_min],
            temp_c: stock.reference_temp_c,
            ..StripSpec::default()
        };
        let strip = strip_for(stock.id, &spec).expect("the strip is built");
        let frame = strip.frames.first().expect("one frame");
        for channel in 0..3 {
            assert!(
                (frame.gamma[channel] - stock.channels[channel].gamma).abs() < 1e-9,
                "channel {channel}: {} then {}",
                stock.channels[channel].gamma,
                frame.gamma[channel]
            );
        }
    }

    #[test]
    fn an_unknown_stock_is_not_a_strip() {
        assert!(strip_for("not_a_film", &StripSpec::default()).is_none());
    }

    #[test]
    fn one_patch_is_allowed_and_sits_at_the_dimmest_exposure() {
        let spec = StripSpec {
            patches: 0,
            ..StripSpec::default()
        };
        let strip = a_strip_with(&spec);
        assert_eq!(strip.frames[0].patches.len(), 1);
        assert!((strip.frames[0].patches[0].log_e - spec.log_e_min).abs() < 1e-12);
    }

    fn a_strip_with(spec: &StripSpec) -> Strip {
        strip_for("vision3_500t", spec).expect("the default stock exists")
    }
}
