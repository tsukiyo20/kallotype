//! The bench's session, across the bridge.
//!
//! A preview is not a print: it never reaches the disk. The session decodes the
//! photograph once and hands back RGBA, so moving the timer is a render and not
//! a decode, a PNG write and a second decode.

use flutter_rust_bridge::frb;
use kallotype_api::preview::{PreviewRequest, PreviewSession as CoreSession};

/// What a preview session is opened on.
#[derive(Debug, Clone)]
pub struct PreviewJob {
    /// The photograph.
    pub input: String,
    /// Film stock id.
    pub film: String,
    /// Paper stock id.
    pub paper: String,
    /// Developer temperature in degrees Celsius.
    pub temp_c: f64,
    /// The width the bench shows the print at.
    pub width: u32,
    /// Expose through the spectral path.
    pub spectral: bool,
    /// Width of the film frame the image represents, in millimetres.
    pub frame_mm: f64,
    /// Add grain.
    pub grain: bool,
    /// Add halation.
    pub halation: bool,
    /// Add DIR couplers.
    pub couplers: bool,
    /// Render on the device when there is one.
    pub gpu: bool,
}

/// One preview frame, ready to become a texture.
#[derive(Debug, Clone)]
pub struct PreviewFrame {
    /// Pixels across.
    pub width: u32,
    /// Pixels down.
    pub height: u32,
    /// RGBA, eight bits per channel, sRGB, row-major.
    pub rgba: Vec<u8>,
}

/// The photograph held on the bench, one decode for many previews.
#[frb(opaque)]
pub struct PreviewSession {
    inner: CoreSession,
}

impl PreviewSession {
    /// Read the photograph once and meter it.
    pub fn open(job: PreviewJob) -> Result<PreviewSession, String> {
        let request = PreviewRequest {
            input: job.input.into(),
            encoding: kallotype_io::InputEncoding::Srgb,
            film: job.film,
            paper: job.paper,
            temp_c: job.temp_c,
            width: job.width,
            spectral: job.spectral,
            frame_mm: job.frame_mm,
            grain: job.grain,
            halation: job.halation,
            couplers: job.couplers,
            gpu: job.gpu,
        };
        let inner = CoreSession::open(request).map_err(|error| error.to_string())?;
        Ok(Self { inner })
    }

    /// The print this session would make at one setting.
    ///
    /// `balance_from` is the strip's one exposure: the enlarger is borrowed
    /// from that development and only the negative is this frame's.
    pub fn frame(
        &self,
        minutes: f64,
        print_ev: f64,
        balance_from: Option<f64>,
        filters: String,
        heat_glass: Option<String>,
    ) -> Result<PreviewFrame, String> {
        let frame = self
            .inner
            .frame(
                minutes,
                print_ev,
                balance_from,
                &filters,
                heat_glass.as_deref(),
            )
            .map_err(|error| error.to_string())?;
        Ok(PreviewFrame {
            width: frame.width,
            height: frame.height,
            rgba: frame.rgba,
        })
    }
}
