//! Argument resolution and the report every command shares.

use kallotype_core::{DevelopmentParams, FilmStock, PaperStock, RenderParams};
use kallotype_core::{film_stock, paper_stock};

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
    /// Side of the baked exposure table, or 0 for no table.
    pub lut_size: usize,
    /// Reflectance CSV for the dictionary prior.
    pub dictionary: Option<std::path::PathBuf>,
    /// A table baked by `kalo bake`.
    pub lut: Option<std::path::PathBuf>,
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
            lut_size: self.lut_size,
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
            return Ok(params.prepare_with_lut(table));
        }

        let atoms = match &self.dictionary {
            None => None,
            Some(path) => {
                let set =
                    kallotype_spectral::load_csv(path).map_err(|error| CliError::Dictionary {
                        path: path.clone(),
                        message: error.to_string(),
                    })?;
                Some(
                    set.samples
                        .iter()
                        .map(|sample| sample.reflectance.clone())
                        .collect::<Vec<_>>(),
                )
            }
        };
        Ok(params.prepare_with(atoms.as_deref()))
    }
}

/// Validate the numeric flags and look up both stocks.
pub fn resolve(stock: &StockArgs) -> Result<Selection, CliError> {
    if !(stock.dev_time.is_finite() && stock.dev_time > 0.0) {
        return Err(CliError::InvalidNumber {
            flag: "--dev",
            value: stock.dev_time,
            expected: "a positive number of minutes",
        });
    }
    if !stock.temp.is_finite() {
        return Err(CliError::InvalidNumber {
            flag: "--temp",
            value: stock.temp,
            expected: "a finite temperature in degrees Celsius",
        });
    }

    let film = film_stock(&stock.film).ok_or_else(|| CliError::UnknownStock {
        kind: "film",
        id: stock.film.clone(),
    })?;
    let paper = paper_stock(&stock.paper).ok_or_else(|| CliError::UnknownStock {
        kind: "paper",
        id: stock.paper.clone(),
    })?;

    let development = DevelopmentParams {
        time_min: stock.dev_time,
        temp_c: stock.temp,
        ..DevelopmentParams::default()
    };

    Ok(Selection {
        development,
        film,
        paper,
        spectral: stock.spectral,
        lut_size: stock.lut_size,
        dictionary: stock.dictionary.clone(),
        lut: stock.lut.clone(),
    })
}

/// Print what the development did, before any pixels are touched.
pub fn print_report(
    params: &RenderParams,
    prepared: &kallotype_core::PreparedRender,
    width: u32,
    height: u32,
) {
    let development = params.development;

    println!("kallotype {}", env!("CARGO_PKG_VERSION"));
    println!("  film      {}  ({})", params.film.id, params.film.label);
    println!("  paper     {}  ({})", params.paper.id, params.paper.label);
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
