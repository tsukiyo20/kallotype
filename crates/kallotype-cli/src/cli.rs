//! The command line surface.

use std::path::PathBuf;

use clap::{Args, Parser, Subcommand, ValueEnum};
use kallotype_io::InputEncoding;

/// Render a linear image through a physical film-and-paper model.
///
/// The model covers the characteristic curve and its dependence on development
/// time and temperature, spectral exposure, dye-based printing and scanning,
/// grain, halation and DIR couplers.
#[derive(Debug, Parser)]
#[command(
    name = "kalo",
    version,
    about = "Kallotype — film simulation, with developing time as a dimension",
    propagate_version = true
)]
pub struct Cli {
    /// The command to run.
    #[command(subcommand)]
    pub command: Command,
}

/// What `kalo` can do.
#[derive(Debug, Subcommand)]
pub enum Command {
    /// Render an image through a film stock and a paper.
    Render(RenderArgs),
    /// List the built-in film and paper stocks.
    Stocks {
        /// Write the catalogue as JSON, for a program to read.
        #[arg(long)]
        json: bool,
    },
    /// Work with a stock file: its provenance, its curves and its spectra.
    Stock {
        /// What to do with it.
        #[command(subcommand)]
        command: StockCommand,
    },
    /// Show what a development does to the curves.
    Curve(CurveArgs),
    /// Bake the spectral exposure into a reusable table.
    Bake(BakeArgs),
}

/// What `kalo stock` can do.
#[derive(Debug, Subcommand)]
pub enum StockCommand {
    /// Check a stock file: provenance, curves and spectra.
    Check(StockCheckArgs),
}

/// `kalo stock check <FILE>`
#[derive(Debug, Args)]
pub struct StockCheckArgs {
    /// The stock file to check.
    pub file: PathBuf,
}

/// Options shared by every command that touches a film and a paper.
#[derive(Debug, Args)]
pub struct StockArgs {
    /// Film stock id (see `kalo stocks`).
    ///
    /// Every built-in stock is digitised from a manufacturer's data sheet; its
    /// file says field by field what was measured and what was borrowed. The
    /// default is the one stock with nothing borrowed at all.
    #[arg(long, default_value = "vision3_500t", conflicts_with = "film_file")]
    pub film: String,

    /// A `.kalofilm` file to render instead of a compiled stock.
    ///
    /// The file carries the film's curves, spectra and a field-by-field account
    /// of what was measured; `data/films/` in the repository has twenty-four.
    /// Loading one needs no recompile, which is the point of the format.
    #[arg(long, value_name = "PATH", conflicts_with = "film")]
    pub film_file: Option<std::path::PathBuf>,

    /// Paper stock id (see `kalo stocks`).
    #[arg(long, default_value = "portra_endura")]
    pub paper: String,

    /// The enlarger's colour pack, in Kodak CC units: `30M`, `20Y+10M`.
    ///
    /// Empty is the model without a filter pack. The dial settings are the
    /// film's own convention — 1 CC is 0.01 of density — and the spectra behind
    /// them are KODAK's tables, so a pack moves the print the way the filter it
    /// names would.
    #[arg(long, value_name = "Y/M/C", default_value = "")]
    pub filters: String,

    /// A heat-absorbing glass in the light path, e.g. `kg3`.
    #[arg(long, value_name = "GLASS")]
    pub heat_glass: Option<String>,

    /// Development time in minutes. Defaults to the time the stock's data
    /// sheet drew its curves at, which is not the same for every film.
    #[arg(long = "dev", value_name = "MINUTES")]
    pub dev_time: Option<f64>,

    /// Developer temperature in degrees Celsius. Defaults to the sheet's.
    #[arg(long, value_name = "C")]
    pub temp: Option<f64>,

    /// Expose through the spectral path instead of the per-channel scalar one.
    #[arg(long)]
    pub spectral: bool,

    /// Bake the spectral exposure into a table of this size per axis.
    /// Requires --spectral. Zero disables the table.
    #[arg(long, value_name = "N", default_value_t = 0)]
    pub lut_size: usize,

    /// Reflectance CSV to use as the spectral dictionary prior. Repeat it to
    /// mix material families into one dictionary. Requires --spectral. Without
    /// it the polynomial prior is used alone.
    #[arg(long, value_name = "PATH")]
    pub dictionary: Vec<std::path::PathBuf>,

    /// Use a table baked by `kalo bake` instead of computing the exposure.
    #[arg(long, value_name = "PATH")]
    pub lut: Option<std::path::PathBuf>,

    /// Load a table even if it was baked for a different camera or film.
    #[arg(long)]
    pub allow_model_mismatch: bool,

    /// Which sensor the input is assumed to have come from.
    ///
    /// `srgb` (the input's own definition, the default), `observer` (CIE 1931,
    /// for input that is already XYZ), `generic` (three broad Gaussians), or a
    /// path to a measured sensitivity CSV. Requires --spectral.
    #[arg(long, value_name = "NAME|PATH")]
    pub camera: Option<String>,

    /// Print through spectral dye absorption and paper layer sensitivities.
    #[arg(long)]
    pub spectral_print: bool,

    /// Scan through spectral reflectance, illuminant and observer.
    #[arg(long)]
    pub spectral_scan: bool,
}

/// `kalo render`
#[derive(Debug, Args)]
pub struct RenderArgs {
    /// Input image. 8/16-bit sRGB by default; pass --input-encoding linear for
    /// a linear-light TIFF. A camera raw (ARW, NEF, CR3, RAF, DNG, ...) is
    /// decoded to linear light directly, if this build has the `raw` feature.
    pub input: PathBuf,

    /// Output image. The extension picks the format (png, tiff, ...).
    #[arg(short, long)]
    pub output: PathBuf,

    /// Film, paper and development.
    #[command(flatten)]
    pub stock: StockArgs,

    /// Exposure offset in stops, applied before the negative.
    ///
    /// Pass `auto` to meter the frame instead of naming the offset: the render
    /// then places the frame's mean luminance at 18 % grey, the way an
    /// averaging exposure meter and a laboratory's average printer both do.
    /// The report says what it solved, so the result can be repeated with a
    /// fixed number. A scene whose key is not the average — a night street, a
    /// snowfield — is better served by a fixed offset.
    #[arg(
        long,
        value_name = "EV|auto",
        default_value = "0",
        allow_hyphen_values = true
    )]
    pub ev: Exposure,

    /// Print exposure in stops, on top of the exposure that prints a mid grey
    /// as a mid grey.
    ///
    /// The print is solved so that an 18 % grey negative lands at the paper's
    /// target: this is the timer, not the balance. Positive is more light and a
    /// darker print, which is what a printer would call "one stop more".
    #[arg(
        long,
        value_name = "EV",
        default_value = "0",
        allow_hyphen_values = true
    )]
    pub print_ev: f64,

    /// How to interpret the values stored in the input file.
    #[arg(long, value_enum, default_value_t = EncodingArg::Srgb)]
    pub input_encoding: EncodingArg,

    /// Add grain to the negative, as a particle process on the film's scale.
    ///
    /// The graininess depends on how much film area a pixel covers, so it needs
    /// --frame-mm to know how big the frame is.
    #[arg(long)]
    pub grain: bool,

    /// Render at this width, in pixels, instead of at the input's own.
    ///
    /// The bench works at the size a screen can show, and a 26 megapixel camera
    /// file is not that. It is a resize and not a crop — the whole frame — and
    /// the grain is computed for the sampling that results, because a smaller
    /// render is a coarser scan and should look like one.
    #[arg(long, value_name = "PIXELS")]
    pub size: Option<u32>,

    /// Width of the film frame the image represents, in millimetres.
    ///
    /// 36 is a 35 mm still frame; use 24 for half-frame, and the short side if
    /// the image is portrait.
    #[arg(long, value_name = "MM", default_value_t = 36.0)]
    pub frame_mm: f64,

    /// Correlation length of the grain in micrometres, overriding the stock's.
    ///
    /// The distance over which neighbouring pixels agree, as measured from a
    /// flat scan by `scripts/grain_spectrum.py` — on a mid-density flat, where
    /// the developed silver is what the scanner sees. Until a stock's own is
    /// measured, the model uses the mean spacing the granularity figure
    /// implies, which is a lower bound.
    ///
    /// Note the stencil: five taps, so a clump much wider than a pixel is
    /// drawn narrower than asked. Below about 3 µm per pixel the render is a
    /// close-up of the film and the kernel is the limit.
    #[arg(long, value_name = "MM")]
    pub grain_um: Option<f64>,

    /// Grain seed. The same seed and the same image give the same grain.
    #[arg(long, value_name = "N", default_value_t = 0)]
    pub grain_seed: u64,

    /// Render on the CPU.
    ///
    /// The GPU is the default: everything the model does — both exposure paths,
    /// grain, halation, the DIR couplers — except a baked table and a dictionary
    /// prior, which are solvers rather than models. A render that needs one, or
    /// a machine with no adapter, falls back to the CPU and says so. Use this
    /// flag to stay on the CPU anyway.
    #[arg(long = "no-gpu", action = clap::ArgAction::SetFalse, default_value_t = true)]
    pub gpu: bool,

    /// Add DIR couplers: development inhibition between layers, with diffusion.
    ///
    /// This is what produces interimage colour correction and the Mackie line
    /// along an edge. The matrix is a placeholder.
    #[arg(long)]
    pub couplers: bool,

    /// Skip the film's own blur, from the measured modulation-transfer curve.
    ///
    /// It is on by default and is a no-op below about 12 megapixels: a 35 mm
    /// frame sampled every 30 µm cannot show a 3 µm blur. Render at 12000 pixels
    /// across and it starts to bite.
    #[arg(long = "no-emulsion")]
    pub no_emulsion: bool,

    /// Add halation: light scattered in the emulsion and reflected off the base.
    ///
    /// Needs --frame-mm for the same reason grain does — the kernels are
    /// expressed in micrometres of film, not in pixels.
    #[arg(long)]
    pub halation: bool,

    /// Add the cyan-sensitive layer's inhibitor (ADR 0018).
    ///
    /// Fuji's fourth layer releases development inhibitor against the
    /// red-sensitive layer instead of forming cyan dye, which is why PRO 400H's
    /// cyan curve shows no second emulsion. The effect is local: it takes cyan
    /// away where that layer sees more cyan light than the frame's average and
    /// lets it through where it sees less, so a uniform frame is unchanged and
    /// an edge is not. Its strength and diffusion length are placeholders, so
    /// this is a demonstration of the mechanism, not a prediction — and it is a
    /// no-op for a stock whose sheet gives no such layer.
    #[arg(long)]
    pub interimage: bool,

    /// Scan the print: the scanner's measured texture, and its optics when
    /// asked for.
    ///
    /// The texture is the one a negative scan showed: 0.60 % of density
    /// through a 48 µm aperture, correlated over 3.2 µm, and mostly common to
    /// the three channels — which is how it was shown to be the scan and not
    /// the film. Until this stage the render is the print's reflectance; this
    /// is what turns it into a scan of the print, noise and all.
    #[arg(long)]
    pub scanner: bool,

    /// Gaussian optics of the scan, in micrometres, on the print.
    ///
    /// Unmeasured, which is why it defaults to off: the scan that measured the
    /// texture cannot separate the optics from the texture that rides on it,
    /// and a point-spread function invented from that measurement would be a
    /// second number pretending to be the first. Enabling it enables --scanner.
    #[arg(long, value_name = "MM", requires = "scanner")]
    pub scan_optics_um: Option<f64>,
}

/// `kalo bake`
#[derive(Debug, Args)]
pub struct BakeArgs {
    /// Output table path, conventionally `.klut`.
    #[arg(short, long)]
    pub output: std::path::PathBuf,

    /// Samples per axis.
    #[arg(long, value_name = "N", default_value_t = 33)]
    pub size: usize,

    /// Reflectance CSV to use as the spectral dictionary prior. Repeat it to
    /// mix material families.
    #[arg(long, value_name = "PATH")]
    pub dictionary: Vec<std::path::PathBuf>,

    /// Which sensor the input is assumed to have come from. Must match the
    /// `--camera` used to render, or the table will be refused.
    #[arg(long, value_name = "NAME|PATH")]
    pub camera: Option<String>,

    /// Which film's layer sensitivities the table is baked against.
    ///
    /// A table holds the film's spectral response, not just the camera's, so it
    /// is only valid for the stock named here. Must match the `--film` used to
    /// render, or the table will be refused.
    #[arg(long, value_name = "ID", default_value = "vision3_500t")]
    pub film: String,
}

/// `kalo curve`
#[derive(Debug, Args)]
pub struct CurveArgs {
    /// Film, paper and development.
    #[command(flatten)]
    pub stock: StockArgs,

    /// Also print the density reached at a few exposure offsets, in stops from
    /// mid grey.
    #[arg(long)]
    pub sweep: bool,
}

/// How to read the input file's numbers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum EncodingArg {
    /// Display-referred sRGB, decoded to linear.
    Srgb,
    /// Already linear light.
    Linear,
}

impl From<EncodingArg> for InputEncoding {
    fn from(value: EncodingArg) -> Self {
        match value {
            EncodingArg::Srgb => Self::Srgb,
            EncodingArg::Linear => Self::Linear,
        }
    }
}

/// How the exposure was given on the command line: a fixed offset, or `auto`.
#[derive(Debug, Clone, Copy, PartialEq)]
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
        match text.parse::<f64>() {
            Ok(ev) => Ok(Self::Stops(ev)),
            Err(_) => Err(format!(
                "expected a number of stops or `auto`, got {text:?}"
            )),
        }
    }
}

impl std::fmt::Display for Exposure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Stops(ev) => write!(formatter, "{ev}"),
            Self::Auto => write!(formatter, "auto"),
        }
    }
}
