//! `kalo contact` — the proof: one exposure, the whole ladder.

use std::path::Path;

use kallotype_core::contact::{ContactSpec, LADDER_MINUTES, SheetGeometry, print, printable};
use kallotype_core::{DevelopmentParams, Metering, film_stock, paper_stock};
use kallotype_io::{Image, load, resize_to_width, save};

use crate::cli::{ContactArgs, Exposure};
use crate::error::CliError;

/// Run the subcommand.
pub fn run(args: ContactArgs) -> Result<(), CliError> {
    let film = film_stock(&args.film).ok_or_else(|| CliError::UnknownStock {
        kind: "film",
        id: args.film.clone(),
    })?;
    if !printable(film) {
        return Err(CliError::Contact {
            message: format!(
                "{} is a reversal — it is its own picture, and there is no contact proof to make",
                film.short
            ),
        });
    }
    let paper = paper_stock(&args.paper).ok_or_else(|| CliError::UnknownStock {
        kind: "paper",
        id: args.paper.clone(),
    })?;

    let times: Vec<f64> = if args.dev.is_empty() {
        LADDER_MINUTES.to_vec()
    } else {
        args.dev.clone()
    };
    if let Some(bad) = times
        .iter()
        .copied()
        .find(|time| !(time.is_finite() && *time > 0.0))
    {
        return Err(CliError::InvalidNumber {
            flag: "--dev",
            value: bad,
            expected: "a positive number of minutes",
        });
    }
    if times.len() > 36 {
        return Err(CliError::Contact {
            message: format!(
                "{} strips is more than one sheet holds; cut the ladder to thirty-six or fewer",
                times.len()
            ),
        });
    }

    let temp = args.temp.unwrap_or(film.reference_temp_c);
    if !temp.is_finite() {
        return Err(CliError::InvalidNumber {
            flag: "--temp",
            value: temp,
            expected: "a finite temperature in degrees Celsius",
        });
    }

    // The sheet is sized first, because the frame has to be sampled at exactly
    // that width: a sheet scaled afterwards would be a lie about the grain and
    // about the size of the film.
    let geometry = SheetGeometry::new(times.len(), args.dpi);
    let source =
        load(&args.input, args.input_encoding.into()).map_err(|source| CliError::Read {
            path: args.input.clone(),
            source,
        })?;
    // A 35 mm frame is 3:2 whatever the file is; a contact proof of a 4:5 file
    // would be a proof of a frame the camera never exposed.
    let cropped = crop(&source, 1.5);
    let frame = sample(&cropped, geometry.frame.0, geometry.frame.1);

    let (exposure_ev, metering) = match args.ev {
        Exposure::Stops(ev) => (ev, None),
        Exposure::Auto => {
            let metered = Metering::of(&frame.pixels);
            (metered.ev, Some(metered))
        }
    };

    let developments: Vec<DevelopmentParams> = times
        .iter()
        .map(|minutes| DevelopmentParams {
            time_min: *minutes,
            temp_c: temp,
            reference_time_min: film.reference_time_min,
            reference_temp_c: film.reference_temp_c,
            ..DevelopmentParams::default()
        })
        .collect();
    let spec = ContactSpec {
        film,
        paper,
        developments,
        exposure_ev,
        print_ev: args.print_ev,
        spectral: args.spectral,
        // The film's blur is on by default in `render` too: a proof is of the
        // film, and the film softens what it carries.
        emulsion: true,
        grain: args.grain,
        halation: args.halation,
        couplers: args.couplers,
        edge_codes: !args.no_edge_codes,
    };

    let contact = print(&frame.pixels, &geometry, &spec);
    let kallotype_core::Contact {
        geometry: sheet,
        pixels,
    } = contact;

    ensure_parent(&args.output)?;
    save(
        &args.output,
        &Image {
            width: sheet.width as u32,
            height: sheet.height as u32,
            pixels,
        },
    )
    .map_err(|source| CliError::Write {
        path: args.output.clone(),
        source,
    })?;

    if let Some(path) = &args.record {
        write_record(path, &sheet)?;
    }

    report(&sheet, &args, &times, temp, exposure_ev, metering);
    Ok(())
}

/// Write what a viewer needs to hit-test the sheet: the frame rects, in pixels.
fn write_record(path: &Path, sheet: &SheetGeometry) -> Result<(), CliError> {
    let frames: Vec<serde_json::Value> = sheet
        .frames
        .iter()
        .map(|frame| {
            serde_json::json!({
                "number": frame.number,
                "minutes": frame.minutes,
                "x": frame.x,
                "y": frame.y,
                "width": frame.width,
                "height": frame.height,
            })
        })
        .collect();
    let record = serde_json::json!({
        "width": sheet.width,
        "height": sheet.height,
        "margin": sheet.margin,
        "dpi": sheet.dpi,
        "frames": frames,
    });
    let text = serde_json::to_string_pretty(&record).map_err(|error| CliError::Contact {
        message: format!("could not write the record: {error}"),
    })?;
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent).map_err(|source| CliError::CreateDir {
                path: parent.to_path_buf(),
                source,
            })?;
        }
    }
    std::fs::write(path, format!("{text}\n")).map_err(|error| CliError::Contact {
        message: format!("could not write {}: {error}", path.display()),
    })
}

fn report(
    sheet: &SheetGeometry,
    args: &ContactArgs,
    times: &[f64],
    temp: f64,
    exposure_ev: f64,
    metering: Option<Metering>,
) {
    let measured = sheet.frames.len();
    let film = film_stock(&args.film).expect("resolved above");
    let listed = times
        .iter()
        .map(|minutes| format!("{minutes:.1}"))
        .collect::<Vec<_>>()
        .join(", ");
    println!("  film      {}", film.label);
    println!(
        "  paper     {}",
        paper_stock(&args.paper).expect("resolved above").label
    );
    println!("  strips    {measured} at {temp:.1} °C — {listed} min");
    match metering {
        Some(metering) => println!(
            "  exposure  auto: {:+.2} EV (mean luminance {:.3})",
            metering.ev, metering.key
        ),
        None => println!("  exposure  {:+.2} EV", exposure_ev),
    }
    let mm = |pixels: usize| pixels as f64 * 25.4 / sheet.dpi;
    println!(
        "  sheet     {}x{} px at {:.0} dpi ({:.0}x{:.0} mm)",
        sheet.width,
        sheet.height,
        sheet.dpi,
        mm(sheet.width),
        mm(sheet.height)
    );
    println!();
    println!(
        "  wrote     {} ({}x{})",
        args.output.display(),
        sheet.width,
        sheet.height
    );
}

/// Centre-crop to an aspect ratio, because a frame is 3:2 whatever the file is.
fn crop(source: &Image, aspect: f64) -> Image {
    let width = source.width as usize;
    let height = source.height as usize;
    if width == 0 || height == 0 {
        return source.clone();
    }
    let (cropped_w, cropped_h) = if width as f64 / height as f64 > aspect {
        (((height as f64 * aspect).round() as usize).max(1), height)
    } else {
        (
            width,
            ((width as f64 / aspect).round() as usize)
                .min(height)
                .max(1),
        )
    };
    let x0 = (width - cropped_w) / 2;
    let y0 = (height - cropped_h) / 2;
    let mut pixels = Vec::with_capacity(cropped_w * cropped_h);
    for row in 0..cropped_h {
        let start = (y0 + row) * width + x0;
        pixels.extend_from_slice(&source.pixels[start..start + cropped_w]);
    }
    Image {
        width: cropped_w as u32,
        height: cropped_h as u32,
        pixels,
    }
}

/// Sample the frame at exactly the sheet's frame size.
///
/// Everything after this reads the photograph at the size the film sees it, so
/// the resize happens before the model and never after the print.
fn sample(source: &Image, width: usize, height: usize) -> Image {
    if width < source.width as usize {
        let scaled = resize_to_width(source, width as u32);
        return fit_rows(&scaled, width, height);
    }
    // A source smaller than the sheet's frame is upsampled rather than refused:
    // a small file still has a proof, and a blocky one is honest about it.
    let mut pixels = Vec::with_capacity(width * height);
    for row in 0..height {
        let source_row = row * source.height as usize / height;
        for column in 0..width {
            let source_column = column * source.width as usize / width;
            pixels.push(source.pixels[source_row * source.width as usize + source_column]);
        }
    }
    Image {
        width: width as u32,
        height: height as u32,
        pixels,
    }
}

/// A row too many, or too few, after the aspect-preserving resize.
fn fit_rows(image: &Image, width: usize, height: usize) -> Image {
    let mut pixels = Vec::with_capacity(width * height);
    for row in 0..height {
        let source_row = row.min(image.height as usize - 1);
        let start = source_row * image.width as usize;
        pixels.extend_from_slice(&image.pixels[start..start + width]);
    }
    Image {
        width: width as u32,
        height: height as u32,
        pixels,
    }
}

fn ensure_parent(path: &Path) -> Result<(), CliError> {
    let Some(parent) = path.parent() else {
        return Ok(());
    };
    if parent.as_os_str().is_empty() {
        return Ok(());
    }
    std::fs::create_dir_all(parent).map_err(|source| CliError::CreateDir {
        path: parent.to_path_buf(),
        source,
    })
}
