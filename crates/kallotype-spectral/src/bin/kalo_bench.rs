//! `kalo-bench` — compare RGB → spectrum reconstructions on the same data.
//!
//! Deliberately dependency-free: this is a tool that has to run anywhere,
//! including on a machine where nothing else has been installed. A handful of
//! flags does not justify pulling in a CLI framework.
//!
//! ```text
//! kalo-bench [--data PATH] [--model all|polynomial|dictionary|sparse]
//!            [--camera cie1931|generic] [--l1 VALUE] [--verbose]
//! ```

use std::path::PathBuf;
use std::process::ExitCode;

use kallotype_spectral::{
    DictionaryUpsampler, PolynomialUpsampler, ReflectanceSet, Sensor, Upsampler, load_csv,
    relative_response_error, rmse, spectral_angle_deg,
};

const DEFAULT_DATA: &str = "data/colorchecker-2005/reflectance.csv";

#[derive(Clone, Copy, PartialEq, Eq)]
enum Model {
    Polynomial,
    Dictionary,
    Sparse,
}

impl Model {
    fn parse(value: &str) -> Result<Vec<Self>, String> {
        Ok(match value {
            "all" => vec![Self::Polynomial, Self::Dictionary],
            "polynomial" => vec![Self::Polynomial],
            "dictionary" => vec![Self::Dictionary],
            "sparse" => vec![Self::Sparse],
            other => return Err(format!("unknown model '{other}'")),
        })
    }

    fn name(self) -> &'static str {
        match self {
            Self::Polynomial => "polynomial",
            Self::Dictionary => "dictionary",
            Self::Sparse => "sparse",
        }
    }
}

#[derive(Clone, Copy)]
enum Camera {
    Cie1931,
    Generic,
}

struct Options {
    data: PathBuf,
    models: Vec<Model>,
    camera: Camera,
    l1: f64,
    verbose: bool,
}

fn main() -> ExitCode {
    let options = match parse_args() {
        Ok(options) => options,
        Err(message) => {
            eprintln!("error: {message}");
            eprintln!(
                "usage: kalo-bench [--data PATH] \
                 [--model all|polynomial|dictionary|sparse] \
                 [--camera cie1931|generic] [--l1 VALUE] [--verbose]"
            );
            return ExitCode::FAILURE;
        }
    };

    match run(&options) {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("error: {message}");
            ExitCode::FAILURE
        }
    }
}

fn parse_args() -> Result<Options, String> {
    let mut data = PathBuf::from(DEFAULT_DATA);
    let mut models = vec![Model::Polynomial, Model::Dictionary];
    let mut camera = Camera::Cie1931;
    let mut l1 = 0.02_f64;
    let mut verbose = false;

    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--data" => data = PathBuf::from(args.next().ok_or("--data needs a path")?),
            "--model" => models = Model::parse(&args.next().ok_or("--model needs a value")?)?,
            "--camera" => {
                camera = match args.next().ok_or("--camera needs a value")?.as_str() {
                    "cie1931" => Camera::Cie1931,
                    "generic" => Camera::Generic,
                    other => return Err(format!("unknown camera '{other}'")),
                };
            }
            "--l1" => {
                l1 = args
                    .next()
                    .ok_or("--l1 needs a value")?
                    .parse()
                    .map_err(|_| "--l1 must be a number".to_owned())?;
            }
            "--verbose" => verbose = true,
            "--help" | "-h" => {
                println!(
                    "usage: kalo-bench [--data PATH] [--model NAME] [--camera NAME] [--l1 VALUE] [--verbose]"
                );
                std::process::exit(0);
            }
            other => return Err(format!("unknown argument '{other}'")),
        }
    }

    Ok(Options {
        data,
        models,
        camera,
        l1,
        verbose,
    })
}

struct Score {
    rmse: f64,
    angle: f64,
    film: [f64; 3],
}

fn run(options: &Options) -> Result<(), String> {
    let set: ReflectanceSet =
        load_csv(&options.data).map_err(|error| format!("{}: {error}", options.data.display()))?;

    let camera = match options.camera {
        Camera::Cie1931 => Sensor::cie1931(&set.grid),
        Camera::Generic => Sensor::generic_camera(&set.grid),
    };
    let film = Sensor::film_layers(&set.grid);

    println!("kallotype bench");
    println!(
        "  dataset   {}  ({} samples, {}-{} nm @ {} nm)",
        set.name,
        set.len(),
        set.grid.start_nm(),
        set.grid.end_nm(),
        set.grid.step_nm()
    );
    println!("  camera    {}  (test instrument)", camera.name());
    println!("  film      {}  (test instrument)", film.name());
    println!(
        "  l1        {:.3}  (only used by the sparse model)",
        options.l1
    );
    println!();

    let mut results: Vec<(&str, Vec<Score>)> = Vec::new();
    for model in &options.models {
        let mut scores = Vec::with_capacity(set.len());
        for sample in &set.samples {
            let response = camera.respond(&sample.reflectance);
            let estimate = match *model {
                Model::Polynomial => PolynomialUpsampler
                    .reconstruct(&response, &camera, &set.grid)
                    .map_err(|error| error.to_string())?,
                Model::Dictionary | Model::Sparse => {
                    // Leave one out: reconstructing a sample from a dictionary
                    // that contains it would measure the dictionary, not the
                    // method.
                    let atoms = set
                        .samples
                        .iter()
                        .filter(|other| other.name != sample.name)
                        .map(|other| other.reflectance.clone())
                        .collect();
                    let mut dictionary = DictionaryUpsampler::new(atoms);
                    if *model == Model::Sparse {
                        dictionary = dictionary.with_l1(options.l1);
                    }
                    dictionary
                        .reconstruct(&response, &camera, &set.grid)
                        .map_err(|error| error.to_string())?
                }
            };

            let film_error = relative_response_error(&film, &sample.reflectance, &estimate);
            let score = Score {
                rmse: rmse(&sample.reflectance, &estimate).map_err(|error| error.to_string())?,
                angle: spectral_angle_deg(&sample.reflectance, &estimate)
                    .map_err(|error| error.to_string())?,
                film: film_error,
            };

            if options.verbose {
                println!(
                    "    {:<11} {:<8} rmse {:.4}  sam {:5.2}°  film ΔR {:>7.2}% {:>7.2}% {:>7.2}%",
                    model.name(),
                    sample.name,
                    score.rmse,
                    score.angle,
                    score.film[0],
                    score.film[1],
                    score.film[2]
                );
            }
            scores.push(score);
        }
        results.push((model.name(), scores));
    }

    if options.verbose {
        println!();
    }

    println!(
        "  {:<12} {:>10} {:>10} {:>14} {:>14}",
        "model", "mean RMSE", "mean SAM", "film |ΔR| avg", "film |ΔR| max"
    );
    for (model, scores) in &results {
        let count = scores.len() as f64;
        let mean_rmse = scores.iter().map(|score| score.rmse).sum::<f64>() / count;
        let mean_angle = scores.iter().map(|score| score.angle).sum::<f64>() / count;
        let mean_film = scores
            .iter()
            .flat_map(|score| score.film.iter().map(|value| value.abs()))
            .sum::<f64>()
            / (count * 3.0);
        let max_film = scores
            .iter()
            .flat_map(|score| score.film.iter().map(|value| value.abs()))
            .fold(0.0_f64, f64::max);

        println!(
            "  {model:<12} {mean_rmse:>10.4} {mean_angle:>9.2}° {mean_film:>13.2}% {max_film:>13.2}%"
        );
    }

    Ok(())
}
