//! The proof, on its own: one exposure of the whole ladder.

use kallotype_api::{contact, resolve, ContactOptions, Exposure, StockChoice};

/// What a proof asks for.
#[derive(Debug, Clone)]
pub struct ContactJob {
    /// The photograph.
    pub input: String,
    /// Film stock id.
    pub film: String,
    /// Paper stock id.
    pub paper: String,
    /// One development per strip, in minutes.
    pub times: Vec<f64>,
    /// Developer temperature in degrees Celsius.
    pub temp_c: f64,
    /// Expose through the spectral path.
    pub spectral: bool,
    /// Meter the frame instead of naming an offset.
    pub ev_auto: bool,
    /// The offset, when the exposure is named.
    pub ev_stops: f64,
    /// Extra print exposure in stops.
    pub print_ev: f64,
    /// Add grain.
    pub grain: bool,
    /// Add halation.
    pub halation: bool,
    /// Add DIR couplers.
    pub couplers: bool,
    /// The proof's resolution.
    pub dpi: f64,
    /// Where the sheet goes.
    pub output: String,
    /// Where the hit-testing record goes.
    pub record: Option<String>,
}

/// The sheet's size and exposure.
#[derive(Debug, Clone)]
pub struct ContactReport {
    /// Width in pixels.
    pub width: u32,
    /// Height in pixels.
    pub height: u32,
    /// The one exposure the sheet was printed at.
    pub exposure_ev: f64,
}

/// Print the ladder on one sheet.
pub fn make_contact(job: ContactJob) -> Result<ContactReport, String> {
    let choice = StockChoice {
        film: job.film,
        paper: job.paper,
        temp: Some(job.temp_c),
        spectral: job.spectral,
        ..StockChoice::default()
    };
    let selection = resolve(&choice).map_err(|error| error.to_string())?;
    let source = kallotype_api::read_input(
        std::path::Path::new(&job.input),
        kallotype_io::InputEncoding::Srgb,
    )
    .map_err(|error| error.to_string())?;
    let options = ContactOptions {
        ev: if job.ev_auto {
            Exposure::Auto
        } else {
            Exposure::Stops(job.ev_stops)
        },
        print_ev: job.print_ev,
        dpi: job.dpi,
        grain: job.grain,
        halation: job.halation,
        couplers: job.couplers,
        edge_codes: true,
        record: job.record.map(Into::into),
    };
    let outcome = contact(
        &source,
        None,
        &selection,
        &job.times,
        &options,
        std::path::Path::new(&job.output),
    )
    .map_err(|error| error.to_string())?;
    Ok(ContactReport {
        width: outcome.geometry.width as u32,
        height: outcome.geometry.height as u32,
        exposure_ev: outcome.exposure_ev,
    })
}
