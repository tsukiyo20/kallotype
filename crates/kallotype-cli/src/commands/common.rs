//! Argument resolution, the input reader, and the report every command shares.

use kallotype_api::StockChoice;
use kallotype_core::{CameraProfile, RenderParams};

use crate::cli::StockArgs;
use crate::error::CliError;

pub use kallotype_api::{Selection, check_model, read_input};

impl From<&StockArgs> for StockChoice {
    fn from(stock: &StockArgs) -> Self {
        Self {
            film: stock.film.clone(),
            paper: stock.paper.clone(),
            filters: stock.filters.clone(),
            heat_glass: stock.heat_glass.clone(),
            dev_time: stock.dev_time,
            temp: stock.temp,
            spectral: stock.spectral,
            lut_size: stock.lut_size,
            dictionary: stock.dictionary.clone(),
            lut: stock.lut.clone(),
            allow_model_mismatch: stock.allow_model_mismatch,
            camera: stock.camera.clone(),
            spectral_print: stock.spectral_print,
            spectral_scan: stock.spectral_scan,
        }
    }
}

/// Validate the numeric flags and look up both stocks.
pub fn resolve(stock: &StockArgs) -> Result<Selection, CliError> {
    kallotype_api::resolve(&StockChoice::from(stock))
}

/// The same, from a choice a command built by hand.
pub fn resolve_stock_choice(choice: &StockChoice) -> Result<Selection, CliError> {
    kallotype_api::resolve(choice)
}

impl From<crate::cli::Exposure> for kallotype_api::Exposure {
    fn from(value: crate::cli::Exposure) -> Self {
        match value {
            crate::cli::Exposure::Stops(ev) => Self::Stops(ev),
            crate::cli::Exposure::Auto => Self::Auto,
        }
    }
}

/// Resolve `--camera` into a profile.
pub(crate) fn camera_profile(value: Option<&str>) -> Result<CameraProfile, CliError> {
    kallotype_api::camera_profile(value)
}

/// Print what the development did, before any pixels are touched.
/// What the render did beyond the model: the effects that were on, and who ran
/// them. Grouped because a report function with eight arguments is a report
/// function that grows one every phase.
pub struct Rendering<'a> {
    /// Grain, if it was on.
    pub grain: Option<&'a kallotype_core::GrainField>,
    /// The emulsion's blur, if it was on.
    pub emulsion: Option<&'a kallotype_core::EmulsionBlur>,
    /// Halation, if it was on.
    pub halation: Option<&'a kallotype_core::Halation>,
    /// DIR couplers, if they were on.
    pub couplers: Option<&'a kallotype_core::Couplers>,
    /// The cyan-sensitive layer's inhibitor, if it was on — ADR 0018.
    pub interimage: Option<&'a kallotype_core::InterImage>,
    /// The scan's texture and optics, if it was on.
    pub scanner: Option<&'a kallotype_core::Scanner>,
    /// What the meter read, if the exposure was metered rather than named.
    pub metering: Option<kallotype_core::Metering>,
    /// Which backend did the work, already formatted.
    pub backend: String,
}

impl Default for Rendering<'_> {
    fn default() -> Self {
        Self {
            grain: None,
            emulsion: None,
            halation: None,
            couplers: None,
            interimage: None,
            scanner: None,
            metering: None,
            backend: "cpu".to_owned(),
        }
    }
}

/// Print what the render did, before the pixels are written.
pub fn print_report(
    params: &RenderParams,
    prepared: &kallotype_core::PreparedRender,
    width: u32,
    height: u32,
    rendering: &Rendering<'_>,
) {
    let development = params.development;

    println!("kallotype {}", env!("CARGO_PKG_VERSION"));
    println!("  backend   {}", rendering.backend);
    println!("  film      {}  ({})", params.film.id, params.film.label);
    println!("  paper     {}  ({})", params.paper.id, params.paper.label);
    println!(
        "  process   {}",
        match params.film.process {
            kallotype_core::FilmProcess::Negative => "negative — developed, printed, scanned",
            kallotype_core::FilmProcess::Reversal => "reversal — the film is the picture",
            kallotype_core::FilmProcess::Monochrome => "monochrome — one record, no dyes",
        }
    );
    println!(
        "  print     {}",
        if prepared.is_spectral_print() {
            "spectral (dye absorption × paper layers)"
        } else {
            "scalar per channel"
        }
    );
    println!(
        "  scan      {}",
        if prepared.is_spectral_scan() {
            "spectral (reflectance × illuminant × CIE 1931)"
        } else {
            "scalar per channel"
        }
    );
    println!(
        "  exposure  {}",
        if prepared.lut().is_some() {
            "spectral, baked table"
        } else if prepared.is_spectral() {
            "spectral, live"
        } else {
            "scalar per channel"
        }
    );
    match rendering.metering {
        Some(metering) => println!(
            "  ev        {:+.2}  auto — frame mean {:.3} → mid grey 0.180",
            params.exposure_ev, metering.key
        ),
        None => println!("  ev        {:+.2}", params.exposure_ev),
    }
    if prepared.is_spectral() || prepared.lut().is_some() {
        println!("  camera    {}", params.camera.name());
    }
    if let Some(interimage) = rendering.interimage {
        println!(
            "  interimage cyan ← the CL layer, gain {:.0} %  σ {:.0} µm  (placeholder)",
            100.0 * interimage.gain,
            interimage.sigma_um
        );
    }
    if let Some(couplers) = rendering.couplers {
        let [row0, row1, row2] = couplers.inhibition;
        println!(
            "  couplers  inhibition R←{:?} G←{:?} B←{:?}  σ {:.0} µm  (placeholder)",
            [row0[0], row0[1], row0[2]],
            [row1[0], row1[1], row1[2]],
            [row2[0], row2[1], row2[2]],
            couplers.sigma_um
        );
    }
    if let Some(emulsion) = rendering.emulsion {
        println!(
            "  blur      σ {:.2}/{:.2}/{:.2} µm, {}  ({})",
            emulsion.sigma_um[0],
            emulsion.sigma_um[1],
            emulsion.sigma_um[2],
            if emulsion.is_noop() {
                "below the pixel"
            } else {
                "applied"
            },
            if params.film.sigma_um.is_some() {
                "the stock's own MTF"
            } else {
                "borrowed: VISION3 H-1-5219 p.3"
            }
        );
    }
    if let Some(halation) = rendering.halation {
        println!(
            "  halation  scatter σ {:.0} µm {:.1}/{:.1}/{:.1} %  reflection σ {:.0} µm {:.1}/{:.1}/{:.1} %  (placeholder)",
            halation.scatter.sigma_um,
            100.0 * halation.scatter.strength[0],
            100.0 * halation.scatter.strength[1],
            100.0 * halation.scatter.strength[2],
            halation.reflection.sigma_um,
            100.0 * halation.reflection.strength[0],
            100.0 * halation.reflection.strength[1],
            100.0 * halation.reflection.strength[2],
        );
    }
    if let Some(grain) = rendering.grain {
        // The clump is worth saying out loud: it is the difference between
        // grain and coloured noise, and it is the one number here that a scan
        // had to measure rather than a data sheet print.
        let clump = if grain.has_kernel() {
            format!(
                ", clump {:.2}/{:.2}/{:.2} µm r{}",
                grain.grain_um[0],
                grain.grain_um[1],
                grain.grain_um[2],
                grain.radius.iter().copied().max().unwrap_or(0)
            )
        } else {
            String::new()
        };
        println!(
            "  grain     {:.2}/{:.2}/{:.2} per µm²  ({:.2} µm pixel, seed {}{})",
            grain.grains_per_um2[0],
            grain.grains_per_um2[1],
            grain.grains_per_um2[2],
            grain.pixel_area_um2.sqrt(),
            grain.seed,
            clump
        );
    }
    if let Some(scanner) = rendering.scanner {
        println!(
            "  scanner   {:.2} µm texture, {:.2} % at 48 µm, {:.0} % common, optics {:.2} µm",
            scanner.texture_um,
            100.0 * scanner.texture_density,
            100.0 * scanner.shared,
            scanner.optics_um
        );
    }
    println!(
        "  develop   {:.2} min @ {:.1} °C  →  {:.2} effective min",
        development.time_min,
        development.temp_c,
        development.effective_time_min()
    );

    let gammas = prepared.channels().map(|channel| channel.gamma);
    println!(
        "  contrast  ×{:.3}  (R {:.3}  G {:.3}  B {:.3})",
        development.gamma_factor(),
        gammas[0],
        gammas[1],
        gammas[2]
    );
    println!("  fog       {:+.3} density", development.fog_delta());
    println!("  ceiling   {:+.3} density", development.d_max_delta());
    println!("  toe       {:+.2} rate", development.toe_delta());
    println!(
        "  speed     {:+.3} log10 E  ({:+.2} stops)",
        development.speed_delta(),
        development.speed_delta() / 2.0_f64.log10()
    );

    if width > 0 {
        println!("  image     {width}x{height}");
    }
}
