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

use kallotype_core::{Densitometer, FilmStock, PaperEmulsion, PaperStock};
use kallotype_view::{StripSpec, strip};

use crate::error::Error;
use crate::selection::{StockChoice, resolve};

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

/// A film's characteristic curve, sampled over its exposure range.
///
/// This is the developed curve itself, not the nine-patch wedge the
/// densitometer reads: a panel that drew the wedge would show a straight line
/// where the film has a toe and a shoulder. Every development of a stock is
/// sampled over the same range, so a strip's curves overlay point for point.
#[derive(Debug, Clone)]
pub struct FilmCurve {
    /// The film.
    pub film: String,
    /// The development.
    pub minutes: f64,
    /// The developer's temperature.
    pub temp_c: f64,
    /// Contrast per layer.
    pub gamma: [f64; 3],
    /// Density floor per layer.
    pub d_min: [f64; 3],
    /// Density ceiling per layer.
    pub d_max: [f64; 3],
    /// The log10 exposures the curve was sampled at.
    pub log_e: Vec<f64>,
    /// The developed density per layer at each sample.
    pub density: Vec<[f64; 3]>,
}

/// The film's developed curve, by id.
pub fn film_curve(id: &str, minutes: f64, temp_c: f64) -> Result<FilmCurve, Error> {
    if !(minutes.is_finite() && minutes > 0.0) {
        return Err(Error::InvalidNumber {
            flag: "--dev",
            value: minutes,
            expected: "a positive number of minutes",
        });
    }
    if !temp_c.is_finite() {
        return Err(Error::InvalidNumber {
            flag: "--temp",
            value: temp_c,
            expected: "a finite temperature",
        });
    }
    let film = kallotype_core::film_stock(id).ok_or_else(|| Error::UnknownStock {
        kind: "film",
        id: id.to_owned(),
    })?;
    let development = kallotype_core::DevelopmentParams {
        time_min: minutes,
        temp_c,
        reference_time_min: film.reference_time_min,
        reference_temp_c: film.reference_temp_c,
        ..kallotype_core::DevelopmentParams::default()
    };
    let curves = film.channels.map(|channel| development.apply_to(channel));
    // The range is the stock's nominal curve, not this development's: the
    // exposure axis is the camera's, and a ladder has to share it.
    let half = film
        .channels
        .iter()
        .map(|channel| 0.5 * channel.amplitude() / channel.gamma.max(1e-9))
        .fold(0.0_f64, f64::max);
    let low = film
        .channels
        .iter()
        .map(|channel| channel.log_e0)
        .fold(f64::INFINITY, f64::min)
        - half
        - 1.0;
    let high = film
        .channels
        .iter()
        .map(|channel| channel.log_e0)
        .fold(f64::NEG_INFINITY, f64::max)
        + half
        + 1.0;
    const SAMPLES: usize = 64;
    let log_e: Vec<f64> = (0..=SAMPLES)
        .map(|i| low + (high - low) * i as f64 / SAMPLES as f64)
        .collect();
    let density: Vec<[f64; 3]> = log_e
        .iter()
        .map(|x| std::array::from_fn(|layer| curves[layer].density(*x)))
        .collect();
    Ok(FilmCurve {
        film: film.id.to_owned(),
        minutes,
        temp_c,
        gamma: curves.map(|curve| curve.gamma),
        d_min: curves.map(|curve| curve.d_min),
        d_max: curves.map(|curve| curve.d_max),
        log_e,
        density,
    })
}

/// A paper's characteristic curve, sampled for a panel to draw.
#[derive(Debug, Clone)]
pub struct PaperChart {
    /// Stable id.
    pub id: String,
    /// The name on the box.
    pub short: String,
    /// `colour` or `silver`.
    pub emulsion: String,
    /// Density of the unexposed paper.
    pub d_min: f64,
    /// Density at full exposure.
    pub d_max: f64,
    /// The straight-line slope.
    pub gamma: f64,
    /// log10 exposure at the middle of the straight line.
    pub log_e0: f64,
    /// Linear reflectance a balanced print reaches for an 18 % grey card.
    pub target_mid_reflectance: f64,
    /// The log10 exposures the curve was sampled at.
    pub log_e: Vec<f64>,
    /// The paper's density at each sample.
    pub density: Vec<f64>,
}

/// A paper's curve, by id.
pub fn paper_chart(id: &str) -> Result<PaperChart, Error> {
    let paper = kallotype_core::paper_stock(id).ok_or_else(|| Error::UnknownStock {
        kind: "paper",
        id: id.to_owned(),
    })?;
    Ok(paper_chart_of(paper))
}

fn paper_chart_of(paper: &PaperStock) -> PaperChart {
    let curve = paper.channel;
    // A decade either side of the curve's own toe and shoulder: enough to see
    // the shape end, not so much that the ends are a flat line.
    let half = 0.5 * curve.amplitude() / curve.gamma.max(1e-9);
    let low = curve.log_e0 - half - 1.0;
    let high = curve.log_e0 + half + 1.0;
    const SAMPLES: usize = 48;
    let log_e: Vec<f64> = (0..=SAMPLES)
        .map(|i| low + (high - low) * i as f64 / SAMPLES as f64)
        .collect();
    let density: Vec<f64> = log_e.iter().map(|x| curve.density(*x)).collect();
    PaperChart {
        id: paper.id.to_owned(),
        short: paper.short.to_owned(),
        emulsion: match paper.emulsion {
            PaperEmulsion::Colour => "colour",
            PaperEmulsion::Silver => "silver",
        }
        .to_owned(),
        d_min: curve.d_min,
        d_max: curve.d_max,
        gamma: curve.gamma,
        log_e0: curve.log_e0,
        target_mid_reflectance: paper.target_mid_reflectance,
        log_e,
        density,
    }
}

/// The print's tone: the paper's curve through one enlarger balance.
#[derive(Debug, Clone)]
pub struct PrintChart {
    /// The film.
    pub film: String,
    /// The paper.
    pub paper: String,
    /// The development the print is made at.
    pub minutes: f64,
    /// The developer's temperature.
    pub temp_c: f64,
    /// The enlarger's exposure per layer, in decades — the balance plus the
    /// timer. Three numbers, because the colour head moves them apart.
    pub shift: [f64; 3],
    /// The negative's log10 exposure, increasing to the right.
    pub log_e: Vec<f64>,
    /// The paper's density per channel at each sample.
    pub density: Vec<[f64; 3]>,
}

/// The print curve, for a film, a paper and a development.
///
/// This is the scalar print's curve, which is the one the model runs unless a
/// caller asks for a spectral print. The x axis is the exposure the negative
/// receives; a longer development moves the negative's density up this curve.
pub fn print_chart(
    film_id: &str,
    paper_id: &str,
    minutes: f64,
    temp_c: f64,
) -> Result<PrintChart, Error> {
    print_chart_with(
        film_id,
        paper_id,
        minutes,
        temp_c,
        &PrintChartOptions::default(),
    )
}

/// The enlarger settings a print curve is drawn under.
#[derive(Debug, Clone, Default)]
pub struct PrintChartOptions {
    /// Extra print exposure in stops, on top of the solved balance.
    pub print_ev: f64,
    /// The enlarger's colour pack, in Kodak CC units.
    pub filters: String,
    /// A heat-absorbing glass in the light path, by name.
    pub heat_glass: Option<String>,
    /// Print through the spectral path.
    pub spectral: bool,
}

/// The print curve under one enlarger setting.
///
/// The timer and the light path are part of the balance, so the curve the panel
/// draws moves when they do. The colour pack and the heat glass are already in
/// the selection; a non-empty pack or a glass turns on the spectral print in
/// the model, and the shift the curve is drawn under includes it.
pub fn print_chart_with(
    film_id: &str,
    paper_id: &str,
    minutes: f64,
    temp_c: f64,
    options: &PrintChartOptions,
) -> Result<PrintChart, Error> {
    if !(minutes.is_finite() && minutes > 0.0) {
        return Err(Error::InvalidNumber {
            flag: "--dev",
            value: minutes,
            expected: "a positive number of minutes",
        });
    }
    let choice = StockChoice {
        film: film_id.to_owned(),
        paper: paper_id.to_owned(),
        dev_time: Some(minutes),
        temp: Some(temp_c),
        filters: options.filters.clone(),
        heat_glass: options.heat_glass.clone(),
        spectral: options.spectral,
        // The curve is the paper under the print; the scan is after it, so
        // only the print stage of the spectral switch belongs here.
        spectral_print: options.spectral,
        ..StockChoice::default()
    };
    let selection = resolve(&choice)?;
    let prepared = selection.prepare_with_film(0.0, options.print_ev, false, selection.film)?;
    let paper = selection.paper.channel;
    let shift = prepared.print_shift();
    // The negative's exposure: clear film at the right, the densest shadow at
    // the left. The paper's curve is shifted by the enlarger's balance.
    let low = -3.5;
    let high = 0.2;
    const SAMPLES: usize = 48;
    let log_e: Vec<f64> = (0..=SAMPLES)
        .map(|i| low + (high - low) * i as f64 / SAMPLES as f64)
        .collect();
    let density: Vec<[f64; 3]> = log_e
        .iter()
        .map(|x| std::array::from_fn(|layer| paper.density(x + shift[layer])))
        .collect();
    Ok(PrintChart {
        film: selection.film.id.to_owned(),
        paper: selection.paper.id.to_owned(),
        minutes,
        temp_c,
        shift,
        log_e,
        density,
    })
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
        assert!(paper_chart("no_such_paper").is_err());
        assert!(print_chart("no_such_film", "portra_endura", 9.0, 20.0).is_err());
    }

    #[test]
    fn the_paper_curve_is_the_papers_own_shape() {
        let chart = paper_chart("portra_endura").expect("the paper exists");
        assert_eq!(chart.log_e.len(), chart.density.len());
        assert!(chart.log_e.len() > 32);
        assert!(chart.density.windows(2).all(|pair| pair[1] >= pair[0]));
        let low = chart.density[0];
        let high = chart.density[chart.density.len() - 1];
        assert!(
            (low - chart.d_min).abs() < 0.02,
            "{low} against {}",
            chart.d_min
        );
        assert!(
            (high - chart.d_max).abs() < 0.05,
            "{high} against {}",
            chart.d_max
        );
        assert!(chart.target_mid_reflectance > 0.0 && chart.target_mid_reflectance < 1.0);
    }

    #[test]
    fn the_film_curve_has_a_toe_and_a_shoulder() {
        let curve = film_curve("vision3_500t", 9.0, 20.0).expect("the film exists");
        assert_eq!(curve.log_e.len(), curve.density.len());
        assert!(curve.log_e.len() > 32);
        for pair in curve.density.windows(2) {
            for (before, after) in pair[0].iter().zip(&pair[1]) {
                assert!(after >= before);
            }
        }
        // The sampled range reaches past both corners: the ends are the
        // plateaus, not the middle of the straight line.
        let first = curve.density[0];
        let last = curve.density[curve.density.len() - 1];
        for channel in 0..3 {
            assert!((first[channel] - curve.d_min[channel]).abs() < 0.02);
            assert!((last[channel] - curve.d_max[channel]).abs() < 0.02);
        }
        let longer = film_curve("vision3_500t", 15.0, 20.0).expect("the film exists");
        assert!(longer.gamma[0] > curve.gamma[0]);
    }

    #[test]
    fn the_print_curve_moves_with_the_timer_and_the_pack() {
        let base =
            print_chart("vision3_500t", "portra_endura", 9.0, 20.0).expect("the stocks exist");
        let over = print_chart_with(
            "vision3_500t",
            "portra_endura",
            9.0,
            20.0,
            &PrintChartOptions {
                print_ev: 1.0,
                ..PrintChartOptions::default()
            },
        )
        .expect("the stocks exist");
        assert!(
            over.shift[0] > base.shift[0],
            "one stop of timer should move the print curve: {:?} against {:?}",
            over.shift,
            base.shift
        );

        let filtered = print_chart_with(
            "vision3_500t",
            "portra_endura",
            9.0,
            20.0,
            &PrintChartOptions {
                filters: "30M".to_owned(),
                ..PrintChartOptions::default()
            },
        )
        .expect("the stocks exist");
        assert_ne!(
            filtered.shift, base.shift,
            "a colour pack is part of the enlarger the curve is drawn under"
        );
    }

    #[test]
    fn the_print_curve_is_the_paper_under_one_balance() {
        let chart =
            print_chart("vision3_500t", "portra_endura", 9.0, 20.0).expect("the stocks exist");
        assert_eq!(chart.log_e.len(), chart.density.len());
        for pair in chart.density.windows(2) {
            for (before, after) in pair[0].iter().zip(&pair[1]) {
                assert!(after >= before);
            }
        }
        // A colour head is unlikely to be perfectly neutral on a measured
        // mask; the three shifts are a balance, not one number repeated.
        assert!(chart.shift.iter().all(|value| value.is_finite()));
        assert!(
            chart.shift[0] != chart.shift[1] || chart.shift[1] != chart.shift[2],
            "a balance with one number on every layer is not a colour head"
        );
    }
}
