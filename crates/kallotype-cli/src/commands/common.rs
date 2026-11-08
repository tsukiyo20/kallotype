//! Argument resolution and the report every command shares.

use kallotype_core::{CameraProfile, DevelopmentParams, FilmStock, PaperStock, RenderParams};
use kallotype_core::{film_stock, paper_stock};
use kallotype_spectral::Sensor;

use crate::cli::StockArgs;
use crate::error::CliError;

/// A stock selection resolved from the command line.
pub struct Selection {
    /// How the negative was developed.
    pub development: DevelopmentParams,
    /// The negative.
    pub film: &'static FilmStock,
    /// The paper.
    pub paper: &'static PaperStock,
    /// Whether to expose through the spectral path.
    pub spectral: bool,
    /// Which sensor the input is assumed to have come from.
    pub camera: CameraProfile,
    /// Side of the baked exposure table, or 0 for no table.
    pub lut_size: usize,
    /// Reflectance CSVs for the dictionary prior.
    pub dictionary: Vec<std::path::PathBuf>,
    /// A table baked by `kalo bake`.
    pub lut: Option<std::path::PathBuf>,
    /// Whether a model mismatch in the table is tolerated.
    pub allow_model_mismatch: bool,
    /// Whether to print through the spectral model.
    pub spectral_print: bool,
    /// Whether to scan through the spectral model.
    pub spectral_scan: bool,
}

impl Selection {
    /// Bundle the selection into the core's render parameters.
    #[must_use]
    pub fn render_params(&self, exposure_ev: f64) -> RenderParams {
        RenderParams {
            film: self.film,
            paper: self.paper,
            development: self.development,
            exposure_ev,
            spectral: self.spectral || self.lut.is_some(),
            camera: self.camera.clone(),
            lut_size: self.lut_size,
            spectral_print: self.spectral_print,
            spectral_scan: self.spectral_scan,
        }
    }
}

impl Selection {
    /// Load the table or dictionary, if requested, and prepare the render.
    pub fn prepare(&self, exposure_ev: f64) -> Result<kallotype_core::PreparedRender, CliError> {
        let params = self.render_params(exposure_ev);

        if let Some(path) = &self.lut {
            let table = kallotype_core::ExposureLut::read(path).map_err(|error| CliError::Lut {
                path: path.clone(),
                message: error.to_string(),
            })?;

            let expected = kallotype_core::SpectralContext::for_stock(self.film).identity();
            if let Err(message) = check_model(table.identity(), &expected) {
                if !self.allow_model_mismatch {
                    return Err(CliError::Lut {
                        path: path.clone(),
                        message,
                    });
                }
                eprintln!("warning: {message}");
            }

            return Ok(params.prepare_with_lut(table));
        }

        let atoms = if self.dictionary.is_empty() {
            None
        } else {
            let mut atoms = Vec::new();
            for path in &self.dictionary {
                let set =
                    kallotype_spectral::load_csv(path).map_err(|error| CliError::Dictionary {
                        path: path.clone(),
                        message: error.to_string(),
                    })?;
                atoms.extend(set.samples.iter().map(|sample| sample.reflectance.clone()));
            }
            Some(atoms)
        };
        Ok(params.prepare_with(atoms.as_deref()))
    }
}

/// Decide whether a table's recorded model matches the one this build implements.
///
/// Split out from the loader so it can be tested without crafting a corrupt file.
pub fn check_model(table: &str, build: &str) -> Result<(), String> {
    if table == build {
        Ok(())
    } else {
        Err(format!(
            "baked for a different model: table says `{table}`, this build is `{build}`. \
             Pass --allow-model-mismatch to use it anyway."
        ))
    }
}

/// Validate the numeric flags and look up both stocks.
pub fn resolve(stock: &StockArgs) -> Result<Selection, CliError> {
    let film = film_stock(&stock.film).ok_or_else(|| CliError::UnknownStock {
        kind: "film",
        id: stock.film.clone(),
    })?;
    let dev_time = stock.dev_time.unwrap_or(film.reference_time_min);
    let temp = stock.temp.unwrap_or(film.reference_temp_c);
    if !(dev_time.is_finite() && dev_time > 0.0) {
        return Err(CliError::InvalidNumber {
            flag: "--dev",
            value: dev_time,
            expected: "a positive number of minutes",
        });
    }
    if !temp.is_finite() {
        return Err(CliError::InvalidNumber {
            flag: "--temp",
            value: temp,
            expected: "a finite temperature in degrees Celsius",
        });
    }

    let paper = paper_stock(&stock.paper).ok_or_else(|| CliError::UnknownStock {
        kind: "paper",
        id: stock.paper.clone(),
    })?;

    // The sheet's development is the reference and the default; `--dev` moves
    // away from it rather than from a number this program invented.
    let development = DevelopmentParams {
        time_min: dev_time,
        temp_c: temp,
        reference_time_min: film.reference_time_min,
        reference_temp_c: film.reference_temp_c,
        ..DevelopmentParams::default()
    };

    Ok(Selection {
        development,
        film,
        paper,
        spectral: stock.spectral,
        camera: camera_profile(stock.camera.as_deref())?,
        lut_size: stock.lut_size,
        dictionary: stock.dictionary.clone(),
        lut: stock.lut.clone(),
        allow_model_mismatch: stock.allow_model_mismatch,
        spectral_print: stock.spectral_print,
        spectral_scan: stock.spectral_scan,
    })
}

/// Resolve `--camera` into a profile.
///
/// Two names are built in; anything else is a path to a CSV imported by
/// a measured sensitivity, with one column per channel named red, green and blue.
pub(crate) fn camera_profile(value: Option<&str>) -> Result<CameraProfile, CliError> {
    let Some(value) = value else {
        return Ok(CameraProfile::default());
    };
    match value {
        "srgb" => Ok(CameraProfile::Srgb),
        "generic" => Ok(CameraProfile::Generic),
        "observer" => Ok(CameraProfile::Observer),
        path => {
            let set = kallotype_spectral::load_csv(path).map_err(|error| CliError::Camera {
                path: path.into(),
                message: error.to_string(),
            })?;
            let channel = |name: &str| {
                set.sample(name)
                    .map(|sample| sample.reflectance.clone())
                    .ok_or_else(|| CliError::Camera {
                        path: path.into(),
                        message: format!("no column named {name:?}"),
                    })
            };
            let channels = [channel("red")?, channel("green")?, channel("blue")?];
            // The dataset name is the directory's; the camera's is the file's.
            let name = std::path::Path::new(path)
                .file_stem()
                .map(|stem| stem.to_string_lossy().into_owned())
                .unwrap_or_else(|| path.to_owned());
            let sensor = Sensor::new(name, channels)
                .map_err(|error| CliError::Camera {
                    path: path.into(),
                    message: error.to_string(),
                })?
                .area_normalized();
            Ok(CameraProfile::Measured(sensor))
        }
    }
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
        println!(
            "  grain     {:.1}/µm²  ({:.2} µm pixel, seed {}, placeholder density)",
            grain.grains_per_um2[0],
            grain.pixel_area_um2.sqrt(),
            grain.seed
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
    println!(
        "  speed     {:+.3} log10 E  ({:+.2} stops)",
        development.speed_delta(),
        development.speed_delta() / 2.0_f64.log10()
    );

    if width > 0 {
        println!("  image     {width}x{height}");
    }
}

#[cfg(test)]
mod tests {
    use super::{camera_profile, check_model};
    use kallotype_core::CameraProfile;

    #[test]
    fn the_built_in_camera_names_resolve() {
        // The default is the sRGB primaries: the input is an sRGB image, and
        // that basis is the one that means what the file says.
        assert!(matches!(camera_profile(None).unwrap(), CameraProfile::Srgb));
        assert!(matches!(
            camera_profile(Some("srgb")).unwrap(),
            CameraProfile::Srgb
        ));
        assert!(matches!(
            camera_profile(Some("generic")).unwrap(),
            CameraProfile::Generic
        ));
        assert!(matches!(
            camera_profile(Some("observer")).unwrap(),
            CameraProfile::Observer
        ));
    }

    #[test]
    fn a_missing_camera_file_names_the_path() {
        let message = camera_profile(Some("/nonexistent/camera.csv")).unwrap_err();
        assert!(
            message.to_string().contains("/nonexistent/camera.csv"),
            "{message}"
        );
    }

    #[test]
    fn a_matching_identity_passes() {
        assert!(check_model("camera=a;film=b", "camera=a;film=b").is_ok());
    }

    #[test]
    fn a_foreign_identity_names_both_sides() {
        let message = check_model("camera=old;film=b", "camera=new;film=b").unwrap_err();
        assert!(message.contains("camera=old"), "{message}");
        assert!(message.contains("camera=new"), "{message}");
        assert!(message.contains("--allow-model-mismatch"), "{message}");
    }
}
