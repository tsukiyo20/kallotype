//! The densitometry behind a print: the wedge, developed and read.
//!
//! The numbers are a densitometer's reading of the strip — the dye plus the
//! base, fog and mask the instrument sees — not the curve evaluated at nine
//! exposures.

use kallotype_api::{chart_for, film_curve, paper_chart, print_chart};

/// One frame's chart.
#[derive(Debug, Clone)]
pub struct ChartFrame {
    /// How long the frame was developed.
    pub minutes: f64,
    /// The developer's temperature.
    pub temp_c: f64,
    /// Contrast of the developed curve in the red, green and blue records.
    pub gamma: Vec<f64>,
    /// The dye's density floor, after fog — above the base, like the curve.
    pub d_min: Vec<f64>,
    /// The dye's density ceiling, above the base, like the curve.
    pub d_max: Vec<f64>,
    /// Status density per patch, nine patches, as the densitometer reads it.
    pub patches: Vec<Vec<f64>>,
    /// The log10 exposure each patch received.
    pub log_e: Vec<f64>,
}

/// Measure a stock's strip at a ladder of development times.
pub fn make_chart(
    film: String,
    times: Vec<f64>,
    temp_c: f64,
) -> Result<Vec<ChartFrame>, String> {
    let frames = chart_for(&film, &times, temp_c).map_err(|error| error.to_string())?;
    Ok(frames
        .into_iter()
        .map(|frame| ChartFrame {
            minutes: frame.minutes,
            temp_c: frame.temp_c,
            gamma: frame.gamma.to_vec(),
            d_min: frame.d_min.to_vec(),
            d_max: frame.d_max.to_vec(),
            patches: frame
                .patches
                .iter()
                .map(|patch| patch.to_vec())
                .collect(),
            log_e: frame.log_e,
        })
        .collect())
}

/// A film's developed curve, for the instrument panel.
#[derive(Debug, Clone)]
pub struct FilmCurveChart {
    /// The film.
    pub film: String,
    /// The development.
    pub minutes: f64,
    /// The developer's temperature.
    pub temp_c: f64,
    /// Contrast per layer.
    pub gamma: Vec<f64>,
    /// Density floor per layer.
    pub d_min: Vec<f64>,
    /// Density ceiling per layer.
    pub d_max: Vec<f64>,
    /// The log10 exposures the curve was sampled at.
    pub log_e: Vec<f64>,
    /// The developed density per layer at each sample.
    pub density: Vec<Vec<f64>>,
}

/// The film's developed curve, by id.
pub fn make_film_curve(
    film: String,
    minutes: f64,
    temp_c: f64,
) -> Result<FilmCurveChart, String> {
    let curve = film_curve(&film, minutes, temp_c).map_err(|error| error.to_string())?;
    Ok(FilmCurveChart {
        film: curve.film,
        minutes: curve.minutes,
        temp_c: curve.temp_c,
        gamma: curve.gamma.to_vec(),
        d_min: curve.d_min.to_vec(),
        d_max: curve.d_max.to_vec(),
        log_e: curve.log_e,
        density: curve
            .density
            .iter()
            .map(|sample| sample.to_vec())
            .collect(),
    })
}

/// A paper's characteristic curve, for the instrument panel.
#[derive(Debug, Clone)]
pub struct PaperCurve {
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

/// The paper's curve, by id.
pub fn make_paper_curve(paper: String) -> Result<PaperCurve, String> {
    let chart = paper_chart(&paper).map_err(|error| error.to_string())?;
    Ok(PaperCurve {
        id: chart.id,
        short: chart.short,
        emulsion: chart.emulsion,
        d_min: chart.d_min,
        d_max: chart.d_max,
        gamma: chart.gamma,
        log_e0: chart.log_e0,
        target_mid_reflectance: chart.target_mid_reflectance,
        log_e: chart.log_e,
        density: chart.density,
    })
}

/// The print's tone: the paper under one enlarger balance.
#[derive(Debug, Clone)]
pub struct PrintCurve {
    /// The film.
    pub film: String,
    /// The paper.
    pub paper: String,
    /// The development the print is made at.
    pub minutes: f64,
    /// The developer's temperature.
    pub temp_c: f64,
    /// The enlarger's exposure per layer, in decades.
    pub shift: Vec<f64>,
    /// The negative's log10 exposure, increasing to the right.
    pub log_e: Vec<f64>,
    /// The paper's density per channel at each sample.
    pub density: Vec<Vec<f64>>,
}

/// The print curve, for a film, a paper and a development.
pub fn make_print_curve(
    film: String,
    paper: String,
    minutes: f64,
    temp_c: f64,
) -> Result<PrintCurve, String> {
    let chart = print_chart(&film, &paper, minutes, temp_c)
        .map_err(|error| error.to_string())?;
    Ok(PrintCurve {
        film: chart.film,
        paper: chart.paper,
        minutes: chart.minutes,
        temp_c: chart.temp_c,
        shift: chart.shift.to_vec(),
        log_e: chart.log_e,
        density: chart
            .density
            .iter()
            .map(|sample| sample.to_vec())
            .collect(),
    })
}
