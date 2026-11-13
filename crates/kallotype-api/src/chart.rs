//! What the developed strip did, as a densitometer reads it.
//!
//! A print is a picture; the chart beside it is the measurement the picture
//! came from. The wedge is `kallotype-view`'s, because that is the one the
//! committed strip was drawn from: nine patches from −2.0 to +0.8 log
//! exposure, the same span in both places, so a chart of a developed roll can
//! be read against the chart the app ships.
//!
//! The numbers are not the curve sampled at nine exposures. They are what an
//! instrument reads off the developed strip: the dye the development formed,
//! plus the base, fog and mask the light also passes through. That is the
//! difference between a characteristic curve and a densitometer reading, and it
//! is the difference the interface's `isMeasured` names.

use kallotype_core::{Densitometer, FilmStock};
use kallotype_view::{StripSpec, strip};

use crate::error::Error;

/// One frame's densitometry, as the interface draws it.
#[derive(Debug, Clone)]
pub struct FrameChart {
    /// How long the frame was developed.
    pub minutes: f64,
    /// The developer's temperature.
    pub temp_c: f64,
    /// Contrast of the developed curve in the red, green and blue records.
    pub gamma: [f64; 3],
    /// The dye's density floor, after fog — above the base, like the curve.
    pub d_min: [f64; 3],
    /// The dye's density ceiling, above the base, like the curve.
    ///
    /// A nine-step strip need not reach it; this is the film's ceiling, not the
    /// densest reading on the strip.
    pub d_max: [f64; 3],
    /// Status density per patch, as the densitometer reads it: the dye plus the
    /// strip's own base, fog and mask.
    pub patches: Vec<[f64; 3]>,
    /// The log10 exposure each patch received.
    pub log_e: Vec<f64>,
}

/// Chart a stock at a ladder of development times.
#[must_use]
pub fn chart(film: &FilmStock, minutes: &[f64], temp_c: f64) -> Vec<FrameChart> {
    let spec = StripSpec {
        minutes: minutes.to_vec(),
        temp_c,
        ..StripSpec::default()
    };
    let instrument = Densitometer::for_stock(film);
    strip(film, &spec)
        .frames
        .into_iter()
        .map(|frame| FrameChart {
            minutes: frame.minutes,
            temp_c: frame.temp_c,
            gamma: frame.gamma,
            d_min: frame.d_min,
            d_max: frame.d_max,
            patches: frame
                .patches
                .iter()
                .map(|patch| instrument.read(patch.dye_density))
                .collect(),
            log_e: frame.patches.iter().map(|patch| patch.log_e).collect(),
        })
        .collect()
}

/// Chart a stock by id.
pub fn chart_for(id: &str, minutes: &[f64], temp_c: f64) -> Result<Vec<FrameChart>, Error> {
    let film = kallotype_core::film_stock(id).ok_or_else(|| Error::UnknownStock {
        kind: "film",
        id: id.to_owned(),
    })?;
    Ok(chart(film, minutes, temp_c))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_chart_is_the_wedge_the_strip_was_drawn_from() {
        let frames = chart_for("vision3_500t", &[3.0, 9.0, 15.0], 20.0).expect("the stock exists");
        assert_eq!(frames.len(), 3);
        for frame in &frames {
            assert_eq!(frame.patches.len(), 9);
            assert_eq!(frame.log_e.len(), 9);
        }
        // The committed strip spans −2.0 to +0.8 log exposure; a chart of a
        // developed roll has to be the same wedge or the two cannot be read
        // against each other.
        assert!((frames[0].log_e[0] + 2.0).abs() < 1e-9);
        assert!((frames[0].log_e[8] - 0.8).abs() < 1e-9);
        // Longer development, more contrast: the ladder has to move.
        assert!(frames[1].gamma[0] > frames[0].gamma[0]);
        assert!(frames[2].gamma[0] > frames[1].gamma[0]);
    }

    #[test]
    fn the_chart_is_the_strips_dye_read_through_its_base() {
        let film = kallotype_core::film_stock("vision3_500t").expect("the stock exists");
        let minutes = [3.0, 9.0, 15.0];
        let spec = StripSpec {
            minutes: minutes.to_vec(),
            temp_c: 20.0,
            ..StripSpec::default()
        };
        let developed = strip(film, &spec);
        let frames = chart(film, &minutes, 20.0);
        let instrument = Densitometer::for_stock(film);

        for (measured, frame) in frames.iter().zip(&developed.frames) {
            for (reading, patch) in measured.patches.iter().zip(&frame.patches) {
                let expected = instrument.read(patch.dye_density);
                for channel in 0..3 {
                    assert!(
                        (reading[channel] - expected[channel]).abs() < 1e-12,
                        "{} min, channel {channel}: {} against {}",
                        frame.minutes,
                        reading[channel],
                        expected[channel]
                    );
                }
            }
            // The reading is gross: the base is in every patch, and the orange
            // mask makes it larger in blue than in red.
            assert!(measured.patches[0][2] > frame.patches[0].dye_density[2] + 0.5);
            assert!(measured.patches[0][0] > frame.patches[0].dye_density[0]);
        }
    }

    #[test]
    fn an_unknown_stock_is_an_error() {
        assert!(chart_for("no_such_film", &[9.0], 20.0).is_err());
    }
}
