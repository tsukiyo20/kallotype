//! One print, at the size a print is.

use kallotype_api::{render, resolve, Exposure, RenderOptions, StockChoice};
use kallotype_io::resize_to_width;

/// What a print asks for.
#[derive(Debug, Clone)]
pub struct PrintJob {
    /// The photograph.
    pub input: String,
    /// Film stock id.
    pub film: String,
    /// Paper stock id.
    pub paper: String,
    /// Development time in minutes.
    pub minutes: f64,
    /// Developer temperature in degrees Celsius.
    pub temp_c: f64,
    /// Width in pixels; zero keeps the photograph's own.
    pub width: u32,
    /// Expose through the spectral path.
    pub spectral: bool,
    /// Meter the frame instead of naming an offset.
    pub ev_auto: bool,
    /// The offset, when the exposure is named.
    pub ev_stops: f64,
    /// Extra print exposure in stops.
    pub print_ev: f64,
    /// Print on the balance solved for this development instead of this one.
    ///
    /// This is a test strip's one exposure: every print keeps the enlarger
    /// where the first print set it.
    pub balance_from: Option<f64>,
    /// The enlarger's colour pack, in Kodak CC units: `30M`, `20Y+10M`.
    pub filters: String,
    /// A heat-absorbing glass in the light path, by name: `kg1` … `kg5`.
    pub heat_glass: Option<String>,
    /// Width of the film frame the image represents, in millimetres.
    pub frame_mm: f64,
    /// Add grain.
    pub grain: bool,
    /// Grain seed.
    pub grain_seed: u64,
    /// Add halation.
    pub halation: bool,
    /// Add DIR couplers.
    pub couplers: bool,
    /// Render on the device.
    pub gpu: bool,
    /// Where the print goes.
    pub output: String,
}

/// What a print produced.
#[derive(Debug, Clone)]
pub struct PrintReport {
    /// Width in pixels.
    pub width: u32,
    /// Height in pixels.
    pub height: u32,
    /// `cpu` or `gpu — …`.
    pub backend: String,
    /// The exposure the print was made at.
    pub exposure_ev: f64,
}

/// Develop and print one frame, at the size the export asks for.
///
/// This is the same pipeline as a roll's frames; it exists separately because a
/// print is rendered from the photograph again, at a size the bench never uses.
pub fn make_print(job: PrintJob) -> Result<PrintReport, String> {
    let choice = StockChoice {
        film: job.film,
        paper: job.paper,
        temp: Some(job.temp_c),
        dev_time: Some(job.minutes),
        filters: job.filters,
        heat_glass: job.heat_glass,
        spectral: job.spectral,
        ..StockChoice::default()
    };
    let selection = resolve(&choice).map_err(|error| error.to_string())?;
    let mut image = kallotype_api::read_input(
        std::path::Path::new(&job.input),
        kallotype_io::InputEncoding::Srgb,
    )
    .map_err(|error| error.to_string())?;
    if job.width > 0 {
        image = resize_to_width(&image, job.width);
    }
    let options = RenderOptions {
        ev: if job.ev_auto {
            Exposure::Auto
        } else {
            Exposure::Stops(job.ev_stops)
        },
        print_ev: job.print_ev,
        balance_from: job.balance_from,
        frame_mm: job.frame_mm,
        grain: job.grain,
        grain_seed: job.grain_seed,
        halation: job.halation,
        couplers: job.couplers,
        gpu: job.gpu,
        ..RenderOptions::default()
    };
    let outcome = render(
        &mut image,
        None,
        &selection,
        &options,
        std::path::Path::new(&job.output),
    )
    .map_err(|error| error.to_string())?;
    Ok(PrintReport {
        width: outcome.width,
        height: outcome.height,
        backend: outcome.backend.to_string(),
        exposure_ev: outcome.params.exposure_ev,
    })
}
