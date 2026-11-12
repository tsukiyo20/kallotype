//! Which stocks, which sensor, which exposure — the choices a render is made of.

use std::path::{Path, PathBuf};

use kallotype_core::{CameraProfile, DevelopmentParams, FilmStock, PaperStock, RenderParams};
use kallotype_core::{film_stock, paper_stock};
use kallotype_spectral::Sensor;

use crate::error::Error;

/// The stock and camera choices a job is made from, before they are resolved.
///
/// The CLI fills this from its flags and the app from its own state; neither
/// shape leaks into the model. A `.kalofilm` file is not here — it is read by
/// the caller that has one and passed as the film of a job, so this crate needs
/// no file format of its own.
#[derive(Debug, Clone)]
pub struct StockChoice {
    /// Film stock id (see `kalo stocks`).
    pub film: String,
    /// Paper stock id.
    pub paper: String,
    /// The enlarger's colour pack, in Kodak CC units: `30M`, `20Y+10M`.
    pub filters: String,
    /// A heat-absorbing glass in the light path, by name.
    pub heat_glass: Option<String>,
    /// Development time in minutes; the stock's reference time when absent.
    pub dev_time: Option<f64>,
    /// Developer temperature in degrees Celsius; the stock's when absent.
    pub temp: Option<f64>,
    /// Expose through the spectral path.
    pub spectral: bool,
    /// Table side per axis for a baked exposure, or 0.
    pub lut_size: usize,
    /// Reflectance CSVs for the dictionary prior.
    pub dictionary: Vec<PathBuf>,
    /// A table baked by `kalo bake`.
    pub lut: Option<PathBuf>,
    /// Load a table even if its recorded model differs from this build's.
    pub allow_model_mismatch: bool,
    /// Which sensor the input is assumed to have come from.
    pub camera: Option<String>,
    /// Print through spectral dye absorption and paper layer sensitivities.
    pub spectral_print: bool,
    /// Scan through spectral reflectance, illuminant and observer.
    pub spectral_scan: bool,
}

impl Default for StockChoice {
    fn default() -> Self {
        Self {
            film: "vision3_500t".to_owned(),
            paper: "portra_endura".to_owned(),
            filters: String::new(),
            heat_glass: None,
            dev_time: None,
            temp: None,
            spectral: false,
            lut_size: 0,
            dictionary: Vec::new(),
            lut: None,
            allow_model_mismatch: false,
            camera: None,
            spectral_print: false,
            spectral_scan: false,
        }
    }
}

/// A stock selection resolved against the model and this build.
#[derive(Clone)]
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
    pub dictionary: Vec<PathBuf>,
    /// A table baked by `kalo bake`.
    pub lut: Option<PathBuf>,
    /// Whether a model mismatch in the table is tolerated.
    pub allow_model_mismatch: bool,
    /// Whether to print through the spectral model.
    pub spectral_print: bool,
    /// The enlarger's colour pack, in Kodak CC units.
    pub filters: kallotype_core::filters::FilterPack,
    /// A heat-absorbing glass in the light path.
    pub heat_glass: Option<kallotype_core::filters::HeatGlass>,
    /// Whether to scan through the spectral model.
    pub spectral_scan: bool,
}

impl Selection {
    /// Bundle the selection into the core's render parameters.
    #[must_use]
    pub fn render_params(
        &self,
        exposure_ev: f64,
        print_ev: f64,
        interimage: bool,
        film: &'static FilmStock,
    ) -> RenderParams {
        RenderParams {
            film,
            paper: self.paper,
            development: self.development,
            exposure_ev,
            print_exposure_ev: print_ev,
            spectral: self.spectral || self.lut.is_some(),
            camera: self.camera.clone(),
            lut_size: self.lut_size,
            spectral_print: self.spectral_print,
            spectral_scan: self.spectral_scan,
            // The layer only exists on some sheets, so the flag that asks for
            // it is the render command's, not the selection's.
            interimage,
            filters: self.filters,
            heat_glass: self.heat_glass,
        }
    }

    /// Load the table or dictionary, if requested, and prepare the render.
    pub fn prepare(
        &self,
        exposure_ev: f64,
        interimage: bool,
    ) -> Result<kallotype_core::PreparedRender, Error> {
        self.prepare_with_film(exposure_ev, 0.0, interimage, self.film)
    }

    /// Prepare a render whose film came from somewhere other than the compiled
    /// table — a `.kalofilm` file, in practice.
    pub fn prepare_with_film(
        &self,
        exposure_ev: f64,
        print_ev: f64,
        interimage: bool,
        film: &'static FilmStock,
    ) -> Result<kallotype_core::PreparedRender, Error> {
        let params = self.render_params(exposure_ev, print_ev, interimage, film);

        if let Some(path) = &self.lut {
            let table = kallotype_core::ExposureLut::read(path).map_err(|error| Error::Lut {
                path: path.clone(),
                message: error.to_string(),
            })?;

            let expected = kallotype_core::SpectralContext::for_stock(film).identity();
            if let Err(message) = check_model(table.identity(), &expected) {
                if !self.allow_model_mismatch {
                    return Err(Error::Lut {
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
                    kallotype_spectral::load_csv(path).map_err(|error| Error::Dictionary {
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

/// Validate the numbers and look up both stocks.
pub fn resolve(stock: &StockChoice) -> Result<Selection, Error> {
    let film = film_stock(&stock.film).ok_or_else(|| Error::UnknownStock {
        kind: "film",
        id: stock.film.clone(),
    })?;
    let dev_time = stock.dev_time.unwrap_or(film.reference_time_min);
    let temp = stock.temp.unwrap_or(film.reference_temp_c);
    if !(dev_time.is_finite() && dev_time > 0.0) {
        return Err(Error::InvalidNumber {
            flag: "--dev",
            value: dev_time,
            expected: "a positive number of minutes",
        });
    }
    if !temp.is_finite() {
        return Err(Error::InvalidNumber {
            flag: "--temp",
            value: temp,
            expected: "a finite temperature in degrees Celsius",
        });
    }

    let paper = paper_stock(&stock.paper).ok_or_else(|| Error::UnknownStock {
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
        filters: parse_filters(&stock.filters)?,
        heat_glass: parse_heat_glass(stock.heat_glass.as_deref())?,
    })
}

/// `30M`, `20Y+10M`, `5C` — the pack an operator would dial.
///
/// One letter per colour, the number in CC units; a bare number is magenta,
/// because that is the dial a colour head actually uses.
fn parse_filters(text: &str) -> Result<kallotype_core::filters::FilterPack, Error> {
    let mut pack = kallotype_core::filters::FilterPack::none();
    for part in text
        .split('+')
        .map(str::trim)
        .filter(|part| !part.is_empty())
    {
        let split = part
            .find(|c: char| c.is_ascii_alphabetic())
            .unwrap_or(part.len());
        let (number, colour) = part.split_at(split);
        let value: f64 = number.trim().parse().map_err(|_| Error::InvalidNumber {
            flag: "--filters",
            value: f64::NAN,
            expected: "a CC setting such as 30M",
        })?;
        match colour.trim().to_ascii_uppercase().as_str() {
            "Y" => pack.yellow = value,
            "M" | "" => pack.magenta = value,
            "C" => pack.cyan = value,
            _ => {
                return Err(Error::InvalidNumber {
                    flag: "--filters",
                    value: f64::NAN,
                    expected: "one of Y, M or C",
                });
            }
        }
    }
    Ok(pack)
}

/// The heat glass by name.
fn parse_heat_glass(
    text: Option<&str>,
) -> Result<Option<kallotype_core::filters::HeatGlass>, Error> {
    use kallotype_core::filters::HeatGlass;
    let Some(text) = text else {
        return Ok(None);
    };
    match text.trim().to_ascii_lowercase().as_str() {
        "kg1" => Ok(Some(HeatGlass::Kg1)),
        "kg2" => Ok(Some(HeatGlass::Kg2)),
        "kg3" => Ok(Some(HeatGlass::Kg3)),
        "kg5" => Ok(Some(HeatGlass::Kg5)),
        _ => Err(Error::InvalidNumber {
            flag: "--heat-glass",
            value: f64::NAN,
            expected: "one of kg1, kg2, kg3, kg5",
        }),
    }
}

/// Resolve `--camera` into a profile.
///
/// Two names are built in; anything else is a path to a CSV imported by
/// a measured sensitivity, with one column per channel named red, green and blue.
pub fn camera_profile(value: Option<&str>) -> Result<CameraProfile, Error> {
    let Some(value) = value else {
        return Ok(CameraProfile::default());
    };
    match value {
        "srgb" => Ok(CameraProfile::Srgb),
        "generic" => Ok(CameraProfile::Generic),
        "observer" => Ok(CameraProfile::Observer),
        path => {
            let set = kallotype_spectral::load_csv(path).map_err(|error| Error::Camera {
                path: path.into(),
                message: error.to_string(),
            })?;
            let channel = |name: &str| {
                set.sample(name)
                    .map(|sample| sample.reflectance.clone())
                    .ok_or_else(|| Error::Camera {
                        path: path.into(),
                        message: format!("no column named {name:?}"),
                    })
            };
            let channels = [channel("red")?, channel("green")?, channel("blue")?];
            // The dataset name is the directory's; the camera's is the file's.
            let name = Path::new(path)
                .file_stem()
                .map(|stem| stem.to_string_lossy().into_owned())
                .unwrap_or_else(|| path.to_owned());
            let sensor = Sensor::new(name, channels)
                .map_err(|error| Error::Camera {
                    path: path.into(),
                    message: error.to_string(),
                })?
                .area_normalized();
            Ok(CameraProfile::Measured(sensor))
        }
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
