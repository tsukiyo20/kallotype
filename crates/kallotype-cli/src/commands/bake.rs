//! `kalo bake` — distil the spectral exposure into a reusable table.

use std::path::Path;

use kallotype_core::{ExposureLut, SpectralContext};

use crate::cli::BakeArgs;
use crate::error::CliError;

/// Run the subcommand.
pub fn run(args: BakeArgs) -> Result<(), CliError> {
    if args.size < 2 {
        return Err(CliError::InvalidNumber {
            flag: "--size",
            value: args.size as f64,
            expected: "an integer of at least 2",
        });
    }

    let film =
        kallotype_core::emulsion::film_stock(&args.film).ok_or_else(|| CliError::UnknownStock {
            kind: "film",
            id: args.film.clone(),
        })?;
    let mut context = SpectralContext::for_stock(film)
        .with_camera(super::common::camera_profile(args.camera.as_deref())?);
    println!("  film {} ({})", film.label, film.note);
    println!("  camera {}", context.camera().name());
    let mut atoms = Vec::new();
    for path in &args.dictionary {
        let set = kallotype_spectral::load_csv(path).map_err(|error| CliError::Dictionary {
            path: path.clone(),
            message: error.to_string(),
        })?;
        atoms.extend(set.samples.iter().map(|sample| sample.reflectance.clone()));
    }
    if !atoms.is_empty() {
        context = context.with_atoms(&atoms);
        println!("  dictionary {} atoms", atoms.len());
    }

    let table = ExposureLut::bake(args.size, &context);

    if let Some(parent) = args.output.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent).map_err(|source| CliError::CreateDir {
                path: parent.to_path_buf(),
                source,
            })?;
        }
    }

    table.write(&args.output).map_err(|error| CliError::Lut {
        path: args.output.clone(),
        message: error.to_string(),
    })?;

    println!(
        "  baked     {} ({size}³ = {} samples, {:.1} MB)",
        args.output.display(),
        args.size * args.size * args.size,
        table.byte_size() as f64 / 1e6,
        size = args.size
    );
    report(&args.output);
    Ok(())
}

fn report(path: &Path) {
    match std::fs::metadata(path) {
        Ok(meta) => println!("  on disk   {:.1} MB", meta.len() as f64 / 1e6),
        Err(_) => println!("  on disk   (unavailable)"),
    }
}
