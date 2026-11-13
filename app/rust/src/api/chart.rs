//! The densitometry behind a print: the wedge, developed and read.
//!
//! The numbers are a densitometer's reading of the strip — the dye plus the
//! base, fog and mask the instrument sees — not the curve evaluated at nine
//! exposures.

use kallotype_api::chart_for;

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
        })
        .collect())
}
