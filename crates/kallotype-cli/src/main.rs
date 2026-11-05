//! `kalo` — the command line front end for Kallotype.

use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Args, Parser, Subcommand, ValueEnum};
use kallotype_core::{
    DevelopmentParams, FilmStock, PaperStock, RenderParams, film_stock, paper_stock, render_pixels,
};
use kallotype_io::{InputEncoding, load, save};

#[derive(Parser)]
#[command(
    name = "kalo",
    version,
    about = "Kallotype — film simulation, with developing time as a dimension",
    long_about = "Render a linear image through a physical film-and-paper model.\n\n\
                  Phase 0 models the characteristic curve and its dependence on \
                  development time and temperature. It does not yet model spectra, \
                  couplers, grain or halation."
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Render an image through a film stock and a paper.
    Render(RenderArgs),
    /// List the built-in film and paper stocks.
    Stocks,
    /// Show what a development does to the curves.
    Curve(CurveArgs),
}

#[derive(Args)]
struct StockArgs {
    /// Film stock id (see `kalo stocks`).
    #[arg(long, default_value = "c41_standard")]
    film: String,

    /// Paper stock id (see `kalo stocks`).
    #[arg(long, default_value = "c41_paper")]
    paper: String,

    /// Development time in minutes.
    #[arg(long = "dev", value_name = "MINUTES", default_value_t = 6.5)]
    dev_time: f64,

    /// Developer temperature in degrees Celsius.
    #[arg(long, value_name = "C", default_value_t = 20.0)]
    temp: f64,
}

#[derive(Args)]
struct RenderArgs {
    /// Input image. 8/16-bit sRGB by default; pass --input-encoding linear for
    /// a linear-light TIFF.
    input: PathBuf,

    /// Output image. The extension picks the format (png, tiff, ...).
    #[arg(short, long)]
    output: PathBuf,

    #[command(flatten)]
    stock: StockArgs,

    /// Exposure offset in stops, applied before the negative.
    #[arg(
        long,
        value_name = "EV",
        default_value_t = 0.0,
        allow_hyphen_values = true
    )]
    ev: f64,

    /// How to interpret the values stored in the input file.
    #[arg(long, value_enum, default_value_t = EncodingArg::Srgb)]
    input_encoding: EncodingArg,
}

#[derive(Args)]
struct CurveArgs {
    #[command(flatten)]
    stock: StockArgs,

    /// Also print the density reached at a few exposure offsets, in stops from
    /// mid grey.
    #[arg(long)]
    sweep: bool,
}

#[derive(Copy, Clone, PartialEq, Eq, ValueEnum)]
enum EncodingArg {
    Srgb,
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

fn main() -> ExitCode {
    match run(Cli::parse()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("error: {message}");
            ExitCode::FAILURE
        }
    }
}

fn run(cli: Cli) -> Result<(), String> {
    match cli.command {
        Command::Render(args) => render(args),
        Command::Stocks => {
            stocks();
            Ok(())
        }
        Command::Curve(args) => curve(args),
    }
}

fn resolve(
    stock: &StockArgs,
) -> Result<(DevelopmentParams, &'static FilmStock, &'static PaperStock), String> {
    if !(stock.dev_time.is_finite() && stock.dev_time > 0.0) {
        return Err(format!("--dev must be positive, got {}", stock.dev_time));
    }
    if !stock.temp.is_finite() {
        return Err(format!("--temp must be a number, got {}", stock.temp));
    }

    let film = film_stock(&stock.film)
        .ok_or_else(|| format!("unknown film stock '{}' (try `kalo stocks`)", stock.film))?;
    let paper = paper_stock(&stock.paper)
        .ok_or_else(|| format!("unknown paper stock '{}' (try `kalo stocks`)", stock.paper))?;

    let development = DevelopmentParams {
        time_min: stock.dev_time,
        temp_c: stock.temp,
        ..DevelopmentParams::default()
    };

    Ok((development, film, paper))
}

fn render(args: RenderArgs) -> Result<(), String> {
    let (development, film, paper) = resolve(&args.stock)?;
    let params = RenderParams {
        film,
        paper,
        development,
        exposure_ev: args.ev,
    };
    let prepared = params.prepare();

    let mut image = load(&args.input, args.input_encoding.into())
        .map_err(|error| format!("could not read {}: {error}", args.input.display()))?;
    let (width, height) = (image.width, image.height);

    render_pixels(&mut image.pixels, &prepared);

    // `out/` is gitignored, so a fresh clone does not have it. Creating the
    // parent keeps `-o out/foo.png` working without a mkdir first.
    if let Some(parent) = args.output.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)
                .map_err(|error| format!("could not create {}: {error}", parent.display()))?;
        }
    }

    save(&args.output, &image)
        .map_err(|error| format!("could not write {}: {error}", args.output.display()))?;

    print_report(&params, width, height);
    println!();
    println!(
        "  wrote     {} ({}x{})",
        args.output.display(),
        width,
        height
    );
    Ok(())
}

fn curve(args: CurveArgs) -> Result<(), String> {
    let (development, film, paper) = resolve(&args.stock)?;
    let params = RenderParams {
        film,
        paper,
        development,
        exposure_ev: 0.0,
    };
    let prepared = params.prepare();

    print_report(&params, 0, 0);

    if args.sweep {
        println!();
        println!("  exposure   R density   G density   B density");
        for stops in [-2.0_f64, -1.0, 0.0, 1.0, 2.0] {
            let log_e = 0.18_f64.log10() + stops * 2.0_f64.log10();
            let densities = prepared.channels().map(|channel| channel.density(log_e));
            println!(
                "  {:>+5.1} EV   {:>9.3}   {:>9.3}   {:>9.3}",
                stops, densities[0], densities[1], densities[2]
            );
        }
    }

    Ok(())
}

fn print_report(params: &RenderParams, width: u32, height: u32) {
    let development = params.development;
    let prepared = params.prepare();

    println!("kallotype {}", env!("CARGO_PKG_VERSION"));
    println!("  film      {}  ({})", params.film.id, params.film.label);
    println!("  paper     {}  ({})", params.paper.id, params.paper.label);
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

fn stocks() {
    println!("film stocks");
    for stock in kallotype_core::FILM_STOCKS {
        println!("  {:<14} {}", stock.id, stock.label);
        println!("  {:<14} {}", "", stock.note);
    }
    println!();
    println!("paper stocks");
    for stock in kallotype_core::PAPER_STOCKS {
        println!("  {:<14} {}", stock.id, stock.label);
        println!("  {:<14} {}", "", stock.note);
    }
}
