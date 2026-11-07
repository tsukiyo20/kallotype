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
    Stocks,
    /// Show what a development does to the curves.
    Curve(CurveArgs),
    /// Bake the spectral exposure into a reusable table.
    Bake(BakeArgs),
}

/// Options shared by every command that touches a film and a paper.
#[derive(Debug, Args)]
pub struct StockArgs {
    /// Film stock id (see `kalo stocks`).
    ///
    /// The default is the one measured stock: its curves are digitised from the
    /// manufacturer's data sheet and its spectra are the ones compiled in. The
    /// others are placeholders, and say so.
    #[arg(long, default_value = "vision3_500t")]
    pub film: String,

    /// Paper stock id (see `kalo stocks`).
    #[arg(long, default_value = "c41_paper")]
    pub paper: String,

    /// Development time in minutes.
    #[arg(long = "dev", value_name = "MINUTES", default_value_t = 6.5)]
    pub dev_time: f64,

    /// Developer temperature in degrees Celsius.
    #[arg(long, value_name = "C", default_value_t = 20.0)]
    pub temp: f64,

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
    /// a linear-light TIFF.
    pub input: PathBuf,

    /// Output image. The extension picks the format (png, tiff, ...).
    #[arg(short, long)]
    pub output: PathBuf,

    /// Film, paper and development.
    #[command(flatten)]
    pub stock: StockArgs,

    /// Exposure offset in stops, applied before the negative.
    #[arg(
        long,
        value_name = "EV",
        default_value_t = 0.0,
        allow_hyphen_values = true
    )]
    pub ev: f64,

    /// How to interpret the values stored in the input file.
    #[arg(long, value_enum, default_value_t = EncodingArg::Srgb)]
    pub input_encoding: EncodingArg,

    /// Add grain to the negative, as a particle process on the film's scale.
    ///
    /// The graininess depends on how much film area a pixel covers, so it needs
    /// --frame-mm to know how big the frame is.
    #[arg(long)]
    pub grain: bool,

    /// Width of the film frame the image represents, in millimetres.
    ///
    /// 36 is a 35 mm still frame; use 24 for half-frame, and the short side if
    /// the image is portrait.
    #[arg(long, value_name = "MM", default_value_t = 36.0)]
    pub frame_mm: f64,

    /// Grain seed. The same seed and the same image give the same grain.
    #[arg(long, value_name = "N", default_value_t = 0)]
    pub grain_seed: u64,

    /// Render on the GPU instead of the CPU.
    ///
    /// Everything the model does — both paths, grain, halation, the DIR
    /// couplers — except a baked table and a dictionary prior, which are
    /// solvers rather than models. A render that needs one falls back to the
    /// CPU and says so. Needs a build with the `gpu` feature;
    /// `cargo install kallotype-cli --features gpu`.
    #[arg(long)]
    pub gpu: bool,

    /// Add DIR couplers: development inhibition between layers, with diffusion.
    ///
    /// This is what produces interimage colour correction and the Mackie line
    /// along an edge. The matrix is a placeholder.
    #[arg(long)]
    pub couplers: bool,

    /// Add halation: light scattered in the emulsion and reflected off the base.
    ///
    /// Needs --frame-mm for the same reason grain does — the kernels are
    /// expressed in micrometres of film, not in pixels.
    #[arg(long)]
    pub halation: bool,
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
