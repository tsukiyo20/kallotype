//! The command line surface.

use std::path::PathBuf;

use clap::{Args, Parser, Subcommand, ValueEnum};
use kallotype_io::InputEncoding;

/// Render a linear image through a physical film-and-paper model.
///
/// Phase 0 models the characteristic curve and its dependence on development
/// time and temperature. It does not yet model spectra, couplers, grain or
/// halation.
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
}

/// Options shared by every command that touches a film and a paper.
#[derive(Debug, Args)]
pub struct StockArgs {
    /// Film stock id (see `kalo stocks`).
    #[arg(long, default_value = "c41_standard")]
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
