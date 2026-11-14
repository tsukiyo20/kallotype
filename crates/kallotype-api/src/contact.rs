//! The proof: the whole ladder on one sheet, exposed once.

use std::path::Path;

use kallotype_core::contact::{
    ContactSpec, LADDER_MINUTES, SheetGeometry, Strips, print, printable,
};
use kallotype_core::{DevelopmentParams, FilmStock, Metering};
use kallotype_io::{Image, resize_to_width, save};

use crate::error::Error;
use crate::render::{Exposure, ensure_parent};
use crate::selection::Selection;

/// Everything a proof needs beyond the photograph and the stocks.
#[derive(Debug, Clone)]
pub struct ContactOptions {
    /// Exposure offset, or metering.
    pub ev: Exposure,
    /// Extra print exposure in stops.
    pub print_ev: f64,
    /// Sheet resolution.
    pub dpi: f64,
    /// Add grain.
    pub grain: bool,
    /// Add halation.
    pub halation: bool,
    /// Add DIR couplers.
    pub couplers: bool,
    /// Stamp the edge codes.
    pub edge_codes: bool,
    /// Where to write the hit-testing record, if anywhere.
    pub record: Option<std::path::PathBuf>,
}

impl Default for ContactOptions {
    fn default() -> Self {
        Self {
            ev: Exposure::Auto,
            print_ev: 0.0,
            dpi: 600.0,
            grain: false,
            halation: false,
            couplers: false,
            edge_codes: true,
            record: None,
        }
    }
}

/// What a proof printed.
pub struct ContactOutcome {
    /// The sheet: size, margins and frame rects.
    pub geometry: SheetGeometry,
    /// The exposure the sheet was printed at.
    pub exposure_ev: f64,
    /// What the meter read, if the exposure was metered.
    pub metering: Option<Metering>,
}

/// Print the ladder on one sheet, and write it where asked.
///
/// The photograph is taken at its own size and sampled to the sheet's frame —
/// not the bench's. A proof is of the film, so its grain has to come from the
/// frame the film carries, which is why this does not accept a pre-shrunk
/// image.
pub fn contact(
    source: &Image,
    film: Option<&'static FilmStock>,
    selection: &Selection,
    times: &[f64],
    options: &ContactOptions,
    output: &Path,
) -> Result<ContactOutcome, Error> {
    let film = film.unwrap_or(selection.film);
    if !printable(film) {
        return Err(Error::Contact {
            message: format!(
                "{} is a reversal — it is its own picture, and there is no contact proof to make",
                film.short
            ),
        });
    }
    if times.is_empty() {
        return Err(Error::Contact {
            message: "a proof needs at least one development".to_owned(),
        });
    }
    if let Some(bad) = times
        .iter()
        .copied()
        .find(|time| !(time.is_finite() && *time > 0.0))
    {
        return Err(Error::InvalidNumber {
            flag: "--dev",
            value: bad,
            expected: "a positive number of minutes",
        });
    }
    if times.len() > 36 {
        return Err(Error::Contact {
            message: format!(
                "{} strips is more than one sheet holds; cut the ladder to thirty-six or fewer",
                times.len()
            ),
        });
    }
    if !options.dpi.is_finite() || options.dpi <= 0.0 {
        return Err(Error::InvalidNumber {
            flag: "--dpi",
            value: options.dpi,
            expected: "a positive number of dots per inch",
        });
    }

    let temp = selection.development.temp_c;
    // A 35 mm frame is 3:2 whatever the file is, in whichever direction the
    // camera was held: a contact proof of a 4:5 file would be a proof of a
    // frame the camera never exposed. A frame made with the camera on its side
    // is not turned on the film — the strip is laid the other way on the paper,
    // which is how a photographer lays out a proof sheet, because the point of
    // one is to look at the pictures.
    let stood = source.height > source.width;
    let geometry = SheetGeometry::new(
        times.len(),
        options.dpi,
        if stood {
            Strips::Vertical
        } else {
            Strips::Horizontal
        },
    );
    let cropped = if stood {
        crop(source, 1.5f64.recip())
    } else {
        crop(source, 1.5)
    };
    // The sheet is sized first, because the frame has to be sampled at exactly
    // that width: a sheet scaled afterwards would be a lie about the grain and
    // about the size of the film.
    let frame = sample(&cropped, geometry.frame.0, geometry.frame.1);
    drop(cropped);

    let (exposure_ev, metering) = match options.ev {
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
            reference_time_min: selection.development.reference_time_min,
            reference_temp_c: selection.development.reference_temp_c,
            ..DevelopmentParams::default()
        })
        .collect();
    let spec = ContactSpec {
        film,
        paper: selection.paper,
        developments,
        exposure_ev,
        print_ev: options.print_ev,
        spectral: selection.spectral,
        // The film's blur is on by default in `render` too: a proof is of the
        // film, and the film softens what it carries.
        emulsion: true,
        grain: options.grain,
        halation: options.halation,
        couplers: options.couplers,
        edge_codes: options.edge_codes,
    };

    let kallotype_core::Contact {
        geometry: sheet,
        pixels,
    } = print(&frame.pixels, &geometry, &spec);

    ensure_parent(output)?;
    save(
        output,
        &Image {
            width: sheet.width as u32,
            height: sheet.height as u32,
            pixels,
        },
    )
    .map_err(|source| Error::Write {
        path: output.to_path_buf(),
        source,
    })?;

    if let Some(path) = &options.record {
        write_record(path, &sheet)?;
    }

    Ok(ContactOutcome {
        geometry: sheet,
        exposure_ev,
        metering,
    })
}

/// The default five-step ladder.
#[must_use]
pub fn ladder() -> &'static [f64] {
    &LADDER_MINUTES
}

/// Write what a viewer needs to hit-test the sheet: the frame rects, in pixels.
fn write_record(path: &Path, sheet: &SheetGeometry) -> Result<(), Error> {
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
    let text = serde_json::to_string_pretty(&record).map_err(|error| Error::Contact {
        message: format!("could not write the record: {error}"),
    })?;
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent).map_err(|source| Error::CreateDir {
                path: parent.to_path_buf(),
                source,
            })?;
        }
    }
    std::fs::write(path, format!("{text}\n")).map_err(|error| Error::Contact {
        message: format!("could not write {}: {error}", path.display()),
    })
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
