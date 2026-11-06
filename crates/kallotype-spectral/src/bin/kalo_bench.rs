//! `kalo-bench` — compare RGB → spectrum reconstructions on the same data.
//!
//! Deliberately dependency-free: this is a tool that has to run anywhere,
//! including on a machine where nothing else has been installed. A handful of
//! flags does not justify pulling in a CLI framework.
//!
//! ```text
//! kalo-bench --data PATH [--model all|polynomial|dictionary|sparse|hybrid]
//!            [--camera cie1931|generic] [--dictionary PATH] [--dictionary-limit N]
//!            [--l1 VALUE] [--hybrid-threshold VALUE] [--verbose]
//! ```

use std::path::PathBuf;
use std::process::ExitCode;

use kallotype_spectral::{
    DictionaryUpsampler, PolynomialUpsampler, ReflectanceSet, Sensor, Spectrum, Upsampler,
    load_csv, relative_response_error, rmse, spectral_angle_deg,
};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Model {
    Polynomial,
    Dictionary,
    Sparse,
    Hybrid,
}

impl Model {
    fn parse(value: &str) -> Result<Vec<Self>, String> {
        Ok(match value {
            "all" => vec![Self::Polynomial, Self::Dictionary, Self::Hybrid],
            "polynomial" => vec![Self::Polynomial],
            "dictionary" => vec![Self::Dictionary],
            "sparse" => vec![Self::Sparse],
            "hybrid" => vec![Self::Hybrid],
            other => return Err(format!("unknown model '{other}'")),
        })
    }

    fn name(self) -> &'static str {
        match self {
            Self::Polynomial => "polynomial",
            Self::Dictionary => "dictionary",
            Self::Sparse => "sparse",
            Self::Hybrid => "hybrid",
        }
    }
}

#[derive(Clone)]
enum Camera {
    Cie1931,
    Generic,
    /// A measured sensitivity: a CSV with `wavelength,red,green,blue` columns.
    Measured(PathBuf),
}

struct Options {
    data: PathBuf,
    models: Vec<Model>,
    camera: Camera,
    l1: f64,
    /// Reconstruct every sample from the union of these datasets instead of
    /// leave-one-out. Any atom whose name matches the target sample's name is
    /// held out, so a dictionary that contains the target family is still a
    /// fair test.
    dictionaries: Vec<PathBuf>,
    /// Cap the dictionary size, so a 24-atom set can be compared with a
    /// 169-atom one without size confounding the result.
    dictionary_limit: Option<usize>,
    /// Relative response residual above which the hybrid falls back.
    hybrid_threshold: f64,
    /// Shift applied to the synthetic camera's peaks, in nanometres.
    camera_shift: f64,
    verbose: bool,
}

fn main() -> ExitCode {
    let options = match parse_args() {
        Ok(options) => options,
        Err(message) => {
            eprintln!("error: {message}");
            eprintln!(
                "usage: kalo-bench [--data PATH] \
                 [--model all|polynomial|dictionary|sparse|hybrid] \
                 [--camera cie1931|generic|PATH] [--dictionary PATH ...] [--dictionary-limit N]
//!            [--l1 VALUE] [--hybrid-threshold VALUE] [--verbose]"
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
    let mut data: Option<PathBuf> = None;
    let mut models = vec![Model::Polynomial, Model::Dictionary, Model::Hybrid];
    let mut camera = Camera::Cie1931;
    let mut l1 = 0.02_f64;
    let mut dictionaries: Vec<PathBuf> = Vec::new();
    let mut dictionary_limit = None;
    let mut hybrid_threshold = 0.02_f64;
    let mut camera_shift = 0.0_f64;
    let mut verbose = false;

    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--data" => data = Some(PathBuf::from(args.next().ok_or("--data needs a path")?)),
            "--model" => models = Model::parse(&args.next().ok_or("--model needs a value")?)?,
            "--camera" => {
                let value = args.next().ok_or("--camera needs a value")?;
                camera = match value.as_str() {
                    "cie1931" => Camera::Cie1931,
                    "generic" => Camera::Generic,
                    path => Camera::Measured(PathBuf::from(path)),
                };
            }
            "--l1" => {
                l1 = args
                    .next()
                    .ok_or("--l1 needs a value")?
                    .parse()
                    .map_err(|_| "--l1 must be a number".to_owned())?;
            }
            "--dictionary" => {
                dictionaries.push(PathBuf::from(
                    args.next().ok_or("--dictionary needs a path")?,
                ));
            }
            "--dictionary-limit" => {
                dictionary_limit = Some(
                    args.next()
                        .ok_or("--dictionary-limit needs a number")?
                        .parse()
                        .map_err(|_| "--dictionary-limit must be an integer".to_owned())?,
                );
            }
            "--hybrid-threshold" => {
                hybrid_threshold = args
                    .next()
                    .ok_or("--hybrid-threshold needs a value")?
                    .parse()
                    .map_err(|_| "--hybrid-threshold must be a number".to_owned())?;
            }
            "--camera-shift" => {
                camera_shift = args
                    .next()
                    .ok_or("--camera-shift needs a value")?
                    .parse()
                    .map_err(|_| "--camera-shift must be a number".to_string())?;
                // The shift is only meaningful for the parameterised camera.
                camera = Camera::Generic;
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

    let data = data.ok_or(
        "--data is required: a reflectance CSV, first column the wavelength and one \
         column per sample",
    )?;
    Ok(Options {
        data,
        models,
        camera,
        l1,
        dictionaries,
        dictionary_limit,
        hybrid_threshold,
        camera_shift,
        verbose,
    })
}

struct Score {
    rmse: f64,
    angle: f64,
    film: [f64; 3],
    fallback: bool,
}

fn run(options: &Options) -> Result<(), String> {
    let set: ReflectanceSet =
        load_csv(&options.data).map_err(|error| format!("{}: {error}", options.data.display()))?;

    // The atom pool is the union of the `--dictionary` files, or the target set
    // itself. Names travel with the atoms so the target sample can be held out
    // by name: a dictionary that contains the target's own material is still a
    // fair test, and a cross-domain dictionary is the case where no name ever
    // matches.
    let mut pool: Vec<(String, Spectrum)> = if options.dictionaries.is_empty() {
        set.samples
            .iter()
            .map(|sample| (sample.name.clone(), sample.reflectance.clone()))
            .collect()
    } else {
        let mut pool = Vec::new();
        for path in &options.dictionaries {
            let other: ReflectanceSet =
                load_csv(path).map_err(|error| format!("{}: {error}", path.display()))?;
            pool.extend(
                other
                    .samples
                    .iter()
                    .map(|sample| (sample.name.clone(), sample.reflectance.resampled(&set.grid))),
            );
        }
        pool
    };
    if let Some(limit) = options.dictionary_limit {
        if limit > 0 && limit < pool.len() {
            let stride = pool.len().div_ceil(limit);
            pool = pool.into_iter().step_by(stride).take(limit).collect();
        }
    }
    let origin = if options.dictionaries.is_empty() {
        format!("{} (leave one out)", set.name)
    } else {
        options
            .dictionaries
            .iter()
            .map(|path| {
                path.file_stem()
                    .map(|stem| stem.to_string_lossy().into_owned())
                    .unwrap_or_else(|| "?".to_owned())
            })
            .collect::<Vec<_>>()
            .join("+")
    };
    println!("  dictionary {origin}  ({} atoms)", pool.len());

    let camera = match &options.camera {
        Camera::Cie1931 => Sensor::cie1931(&set.grid),
        Camera::Generic => Sensor::generic_camera_shifted(&set.grid, options.camera_shift),
        Camera::Measured(path) => {
            let curves = load_csv(path).map_err(|error| format!("{}: {error}", path.display()))?;
            let channel = |name: &str| {
                curves
                    .sample(name)
                    .map(|sample| sample.reflectance.resampled(&set.grid))
                    .ok_or_else(|| format!("{}: no column named {name:?}", path.display()))
            };
            let sensor = Sensor::new(
                path.file_stem()
                    .map(|stem| stem.to_string_lossy().into_owned())
                    .unwrap_or_else(|| "measured".to_owned()),
                [channel("red")?, channel("green")?, channel("blue")?],
            )
            .map_err(|error| error.to_string())?;
            // White-balanced input, not raw: each channel is divided by its
            // own area so a neutral triple reconstructs to a neutral spectrum.
            sensor.area_normalized()
        }
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

            // Reconstructing a sample from an atom that *is* that sample would
            // measure the dictionary, not the method.
            let atoms: Vec<Spectrum> = pool
                .iter()
                .filter(|(name, _)| *name != sample.name)
                .map(|(_, spectrum)| spectrum.clone())
                .collect();

            let (estimate, fell_back) = match *model {
                Model::Polynomial => (
                    PolynomialUpsampler
                        .reconstruct(&response, &camera, &set.grid)
                        .map_err(|error| error.to_string())?,
                    false,
                ),
                Model::Dictionary | Model::Sparse | Model::Hybrid => {
                    let mut dictionary = DictionaryUpsampler::new(atoms);
                    if *model == Model::Sparse {
                        dictionary = dictionary.with_l1(options.l1);
                    }
                    let from_dictionary = dictionary
                        .reconstruct(&response, &camera, &set.grid)
                        .map_err(|error| error.to_string())?;

                    if *model == Model::Hybrid {
                        // If the mixture cannot reproduce the measurement, the
                        // dictionary does not cover this material; fall back to
                        // the smooth prior rather than inventing a wrong answer.
                        let measured = camera.respond(&from_dictionary);
                        let residual: f64 = (0..3)
                            .map(|index| (measured[index] - response[index]).powi(2))
                            .sum::<f64>()
                            .sqrt();
                        let scale: f64 = (0..3)
                            .map(|index| response[index].powi(2))
                            .sum::<f64>()
                            .sqrt()
                            .max(1e-9);
                        if residual / scale > options.hybrid_threshold {
                            (
                                PolynomialUpsampler
                                    .reconstruct(&response, &camera, &set.grid)
                                    .map_err(|error| error.to_string())?,
                                true,
                            )
                        } else {
                            (from_dictionary, false)
                        }
                    } else {
                        (from_dictionary, false)
                    }
                }
            };

            let film_error = relative_response_error(&film, &sample.reflectance, &estimate);
            let score = Score {
                rmse: rmse(&sample.reflectance, &estimate).map_err(|error| error.to_string())?,
                angle: spectral_angle_deg(&sample.reflectance, &estimate)
                    .map_err(|error| error.to_string())?,
                film: film_error,
                fallback: fell_back,
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
        "  {:<12} {:>10} {:>10} {:>14} {:>14} {:>10}",
        "model", "mean RMSE", "mean SAM", "film |ΔR| avg", "film |ΔR| max", "fallback"
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

        let fallbacks = scores.iter().filter(|score| score.fallback).count();
        let fallback_rate = 100.0 * fallbacks as f64 / count;
        println!(
            "  {model:<12} {mean_rmse:>10.4} {mean_angle:>9.2}° {mean_film:>13.2}% {max_film:>13.2}% {fallback_rate:>9.1}%"
        );
    }

    Ok(())
}
