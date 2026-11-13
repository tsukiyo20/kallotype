//! A roll: one photograph, one read, five prints and a proof.

use crate::frb_generated::StreamSink;
use kallotype_api::{resolve, roll, Exposure, Progress, RollRequest, StockChoice};

/// What the bench asks for.
#[derive(Debug, Clone)]
pub struct RollJob {
    /// The photograph.
    pub input: String,
    /// Film stock id.
    pub film: String,
    /// Paper stock id.
    pub paper: String,
    /// One development per frame, in minutes.
    pub times: Vec<f64>,
    /// Developer temperature in degrees Celsius.
    pub temp_c: f64,
    /// The width the bench shows.
    pub width: u32,
    /// Expose through the spectral path.
    pub spectral: bool,
    /// Meter the frame instead of naming an offset.
    pub ev_auto: bool,
    /// The offset, when the exposure is named.
    pub ev_stops: f64,
    /// Extra print exposure in stops.
    pub print_ev: f64,
    /// The enlarger's colour pack, in Kodak CC units.
    pub filters: String,
    /// A heat-absorbing glass in the light path, by name.
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
    /// One output per development, in the ladder's order.
    pub frames: Vec<String>,
    /// Where the proof goes.
    pub contact: Option<String>,
    /// Where the proof's hit-testing record goes.
    pub record: Option<String>,
    /// The proof's resolution.
    pub dpi: f64,
}

/// Where a roll has got to.
#[derive(Debug, Clone)]
pub struct RollProgress {
    /// How many pieces are done.
    pub done: u32,
    /// How many there are.
    pub total: u32,
    /// `frame` or `contact` or `done`.
    pub stage: String,
}

/// Develop a roll.
///
/// This is the call the bench makes: it reads the photograph once, prints the
/// ladder, prints the proof, and reports each piece as it lands. The work runs
/// on the bridge's thread pool, so the interface never waits on it.
pub fn make_roll(job: RollJob, progress: StreamSink<RollProgress>) -> Result<(), String> {
    let choice = StockChoice {
        film: job.film,
        paper: job.paper,
        temp: Some(job.temp_c),
        filters: job.filters,
        heat_glass: job.heat_glass,
        spectral: job.spectral,
        ..StockChoice::default()
    };
    let selection = resolve(&choice).map_err(|error| error.to_string())?;
    let request = RollRequest {
        input: job.input.into(),
        input_encoding: kallotype_io::InputEncoding::Srgb,
        frames: job.frames.into_iter().map(Into::into).collect(),
        contact: job.contact.map(Into::into),
        record: job.record.map(Into::into),
        times: job.times,
        size: job.width,
        dpi: job.dpi,
        ev: if job.ev_auto {
            Exposure::Auto
        } else {
            Exposure::Stops(job.ev_stops)
        },
        print_ev: job.print_ev,
        frame_mm: job.frame_mm,
        grain: job.grain,
        grain_um: None,
        grain_seed: job.grain_seed,
        halation: job.halation,
        couplers: job.couplers,
        gpu: job.gpu,
    };
    let total = request.times.len() as u32;
    roll(&request, &selection, None, &mut |progress_event| {
        let event = match progress_event {
            Progress::Frame { index, total } => RollProgress {
                done: index as u32,
                total: total as u32,
                stage: "frame".to_owned(),
            },
            Progress::Contact => RollProgress {
                done: total,
                total,
                stage: "contact".to_owned(),
            },
            Progress::Done => RollProgress {
                done: total,
                total,
                stage: "done".to_owned(),
            },
        };
        // A closed sink is the interface saying it is no longer watching; the
        // work is still worth finishing.
        let _ = progress.add(event);
    })
    .map_err(|error| error.to_string())?;

    Ok(())
}
