//! One photograph, developed at one time and printed on one paper.

use std::path::Path;

use kallotype_core::{
    Couplers, EmulsionBlur, Finishing, GrainField, Halation, InterImage, Metering, RenderParams,
    Scanner, render_pixels_finished,
};
use kallotype_io::{Image, save};

use crate::error::Error;
use crate::selection::Selection;

/// How the exposure is chosen.
#[derive(Debug, Clone, Copy)]
pub enum Exposure {
    /// A fixed offset in stops.
    Stops(f64),
    /// Meter the frame and place its mean luminance at 18 % grey.
    Auto,
}

impl std::str::FromStr for Exposure {
    type Err = String;

    fn from_str(text: &str) -> Result<Self, Self::Err> {
        if text.eq_ignore_ascii_case("auto") {
            return Ok(Self::Auto);
        }
        text.parse::<f64>()
            .map(Self::Stops)
            .map_err(|error| format!("expected a number of stops or `auto`: {error}"))
    }
}

/// Everything a render needs beyond the image and the stocks.
#[derive(Debug, Clone)]
pub struct RenderOptions {
    /// Exposure offset, or metering.
    pub ev: Exposure,
    /// Extra print exposure in stops.
    pub print_ev: f64,
    /// Print on the balance solved for this development instead of this one.
    ///
    /// A test strip is one exposure: every print is made with the enlarger
    /// where the first print set it, so that what changes between the prints is
    /// the development and not the timer. The reference is a development time
    /// of the same film and paper; the print keeps its own negative.
    pub balance_from: Option<f64>,
    /// Width of the film frame the image represents, in millimetres.
    pub frame_mm: f64,
    /// Add the emulsion's own blur.
    pub emulsion: bool,
    /// Add halation.
    pub halation: bool,
    /// Add DIR couplers.
    pub couplers: bool,
    /// Add the cyan-sensitive layer's inhibitor.
    pub interimage: bool,
    /// Add grain.
    pub grain: bool,
    /// Override the grain's correlation length.
    pub grain_um: Option<f64>,
    /// Grain seed.
    pub grain_seed: u64,
    /// Scan the print.
    pub scanner: bool,
    /// Gaussian optics of the scan, in micrometres.
    pub scan_optics_um: Option<f64>,
    /// Render on the GPU when there is one.
    pub gpu: bool,
}

impl Default for RenderOptions {
    fn default() -> Self {
        Self {
            ev: Exposure::Auto,
            print_ev: 0.0,
            balance_from: None,
            frame_mm: 36.0,
            emulsion: true,
            halation: false,
            couplers: false,
            interimage: false,
            grain: false,
            grain_um: None,
            grain_seed: 0,
            scanner: false,
            scan_optics_um: None,
            gpu: true,
        }
    }
}

/// Which renderer did the work.
#[derive(Debug, Clone)]
pub enum Backend {
    /// The `kallotype-core` model, in f64.
    Cpu,
    /// The device, as wgpu describes it.
    Gpu(String),
}

impl std::fmt::Display for Backend {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Cpu => write!(formatter, "cpu"),
            Self::Gpu(name) => write!(formatter, "gpu — {name}"),
        }
    }
}

/// The finishing stages, owned, so an outcome can outlive the call that made it.
#[derive(Debug, Default)]
pub struct OwnedFinishing {
    /// The emulsion's blur, if it was on.
    pub emulsion: Option<EmulsionBlur>,
    /// Halation, if it was on.
    pub halation: Option<Halation>,
    /// Grain, if it was on.
    pub grain: Option<GrainField>,
    /// DIR couplers, if they were on.
    pub couplers: Option<Couplers>,
    /// The cyan-sensitive layer's inhibitor, if it was on.
    pub interimage: Option<InterImage>,
}

impl OwnedFinishing {
    /// Borrow the stages for a render call.
    #[must_use]
    pub fn as_finishing(&self) -> Finishing<'_> {
        Finishing {
            emulsion: self.emulsion.as_ref(),
            halation: self.halation.as_ref(),
            grain: self.grain.as_ref(),
            couplers: self.couplers.as_ref(),
            interimage: self.interimage.as_ref(),
        }
    }
}

/// What a render did.
pub struct RenderOutcome {
    /// Width in pixels.
    pub width: u32,
    /// Height in pixels.
    pub height: u32,
    /// Who rendered it.
    pub backend: Backend,
    /// The parameters the model was run with.
    pub params: RenderParams,
    /// The curves, after the development.
    pub prepared: kallotype_core::PreparedRender,
    /// The finishing stages that were on.
    pub finishing: OwnedFinishing,
    /// The scan's texture and optics, if it was on.
    pub scanner: Option<Scanner>,
    /// What the meter read, if the exposure was metered.
    pub metering: Option<Metering>,
    /// Things the caller should say out loud but that did not stop the render.
    pub warnings: Vec<String>,
}

/// Develop a whole image and write it where asked.
///
/// The image is taken at the size it will be rendered at: the meter averages
/// it, the grain is scaled by it, and the emulsions blur across it, so a
/// caller that resizes afterwards would be rendering a different photograph.
/// `film` overrides the stock the selection resolved to — that is how a
/// `.kalofilm` file reaches the model without this crate knowing the format.
pub fn render(
    image: &mut Image,
    film: Option<&'static kallotype_core::FilmStock>,
    selection: &Selection,
    options: &RenderOptions,
    output: &Path,
) -> Result<RenderOutcome, Error> {
    let film = film.unwrap_or(selection.film);
    let (width, height) = (image.width, image.height);
    let (width, height) = (width as usize, height as usize);

    // The meter reads the frame, and the offset it solves is part of the
    // parameters, so it runs between the decode and the prepare.
    let (exposure_ev, metering) = match options.ev {
        Exposure::Stops(ev) => (ev, None),
        Exposure::Auto => {
            let metered = Metering::of(&image.pixels);
            (metered.ev, Some(metered))
        }
    };

    // The flag is asked for before anything is prepared: the fourth integral is
    // part of the model, not a pass over a finished density.
    let interimage = options.interimage && film.cl_layer.is_some();
    let prepared = selection.prepare_with_film(exposure_ev, options.print_ev, interimage, film)?;
    let prepared = match options.balance_from {
        Some(minutes) => {
            if !(minutes.is_finite() && minutes > 0.0) {
                return Err(Error::InvalidNumber {
                    flag: "--balance-from",
                    value: minutes,
                    expected: "a positive number of minutes",
                });
            }
            let mut reference = selection.clone();
            reference.development.time_min = minutes;
            let reference =
                reference.prepare_with_film(exposure_ev, options.print_ev, interimage, film)?;
            prepared.printed_like(&reference)
        }
        None => prepared,
    };
    let params = selection.render_params(exposure_ev, options.print_ev, interimage, film);

    let pixel_um = options.frame_mm * 1000.0 / width.max(1) as f64;
    // The field takes its grain density from the stock: the measured one
    // differs by a factor of nine between its layers, and a stock without a
    // measurement falls back to the placeholder.
    let grain = options.grain.then(|| {
        let field =
            GrainField::for_stock(width, height, options.frame_mm, options.grain_seed, film);
        match options.grain_um {
            Some(diameter) => field.with_grain_sizes([diameter; 3]),
            None => field,
        }
    });
    let emulsion = options
        .emulsion
        .then(|| EmulsionBlur::for_stock(film, pixel_um));
    let halation = options.halation.then(|| Halation::typical(pixel_um));
    let couplers = options.couplers.then(|| Couplers::typical(pixel_um));
    let interimage_field = interimage.then(|| InterImage::typical(pixel_um));
    let finishing = OwnedFinishing {
        emulsion,
        halation,
        grain,
        couplers,
        interimage: interimage_field,
    };

    let mut warnings = Vec::new();
    let backend = render_pixels(
        &mut image.pixels,
        &prepared,
        width,
        height,
        &finishing.as_finishing(),
        options.gpu,
        &mut warnings,
    )?;

    // The scan stage is a post-pass on the finished print, so it is the same
    // arithmetic whichever backend drew the pixels: the scanner is not part of
    // the film, and it is not part of either renderer either.
    let scanner = options.scanner.then(|| {
        let mut scanner = Scanner::measured();
        if let Some(optics) = options.scan_optics_um {
            scanner.optics_um = optics;
        }
        scanner
    });
    if let Some(scanner) = scanner.as_ref() {
        scanner.apply(&mut image.pixels, width, height, pixel_um);
    }

    ensure_parent(output)?;
    save(output, image).map_err(|source| Error::Write {
        path: output.to_path_buf(),
        source,
    })?;

    Ok(RenderOutcome {
        width: width as u32,
        height: height as u32,
        backend,
        params,
        prepared,
        finishing,
        scanner,
        metering,
        warnings,
    })
}

/// Render the pixels, on the GPU if asked and possible, on the CPU otherwise.
///
/// The fallback is deliberate and loud. A machine with no adapter, or a render
/// the backend does not implement, gets a warning and a correct image, not an
/// error and not a silently different one.
#[cfg(feature = "gpu")]
fn render_pixels(
    pixels: &mut [[f64; 3]],
    prepared: &kallotype_core::PreparedRender,
    width: usize,
    height: usize,
    finishing: &Finishing,
    on_gpu: bool,
    warnings: &mut Vec<String>,
) -> Result<Backend, Error> {
    if !on_gpu {
        render_pixels_finished(pixels, prepared, width, height, finishing);
        return Ok(Backend::Cpu);
    }

    let gpu = match kallotype_gpu::Gpu::new() {
        Ok(gpu) => gpu,
        Err(error) => {
            warnings.push(format!("{error}; rendering on the cpu"));
            render_pixels_finished(pixels, prepared, width, height, finishing);
            return Ok(Backend::Cpu);
        }
    };

    match gpu.render_finished(pixels, prepared, width, height, finishing) {
        Ok(rendered) => {
            pixels.copy_from_slice(&rendered);
            Ok(Backend::Gpu(gpu.describe()))
        }
        // The backend names what it cannot do — a table, a dictionary — and
        // asking it is what decides: the API keeps no second list of supported
        // stages to drift out of step with the crate's.
        Err(kallotype_gpu::GpuError::Unsupported(stage)) => {
            warnings.push(format!(
                "the gpu backend does not implement {stage} yet; rendering on the cpu"
            ));
            render_pixels_finished(pixels, prepared, width, height, finishing);
            Ok(Backend::Cpu)
        }
        Err(error) => Err(Error::Gpu {
            message: error.to_string(),
        }),
    }
}

/// Without the feature there is no device to ask for, so the render is the CPU's
/// and the report says so. A build that cannot honour the default must not fail
/// because of it.
#[cfg(not(feature = "gpu"))]
fn render_pixels(
    pixels: &mut [[f64; 3]],
    prepared: &kallotype_core::PreparedRender,
    width: usize,
    height: usize,
    finishing: &Finishing,
    on_gpu: bool,
    warnings: &mut Vec<String>,
) -> Result<Backend, Error> {
    if on_gpu {
        warnings.push("this build has no GPU backend; rendering on the cpu".to_owned());
    }
    render_pixels_finished(pixels, prepared, width, height, finishing);
    Ok(Backend::Cpu)
}

/// Create the output's directory, so `-o out/foo.png` works on a fresh clone.
pub(crate) fn ensure_parent(path: &Path) -> Result<(), Error> {
    let Some(parent) = path.parent() else {
        return Ok(());
    };
    if parent.as_os_str().is_empty() {
        return Ok(());
    }
    std::fs::create_dir_all(parent).map_err(|source| Error::CreateDir {
        path: parent.to_path_buf(),
        source,
    })
}
