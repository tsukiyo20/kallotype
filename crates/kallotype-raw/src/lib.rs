//! Camera raw decoding for `kalo`.
//!
//! # Why this is a separate crate
//!
//! A camera raw file is not an image. It is a sensor mosaic plus a small pile
//! of metadata — black level, white balance as shot, the camera's own colour
//! matrix — and turning it into pixels means demosaicing and colour conversion.
//! The rest of Kallotype is MIT or Apache-2.0; the only maintained Rust libraries that
//! do that work (`rawler`, `rawloader`) are LGPL-2.1. Rather than relicense the
//! whole project or hand-write thirty decoders, the decoder lives here, out of
//! the workspace, and is linked only when someone asks for it:
//!
//! ```text
//! cargo build --release --bin kalo --features kallotype-cli/raw
//! ```
//!
//! A binary built without that feature contains no LGPL code, and `cargo deny`
//! on the workspace never sees `rawler` at all — this crate is excluded from
//! it. A binary built *with* the feature is a combined work and carries
//! LGPL-2.1 obligations.
//!
//! # What comes out
//!
//! Scene-referred linear sRGB, in the same shape as
//! [`kallotype_io::load`]'s linear output, which is what the renderer's
//! spectral front end wants. That is the whole point of reading raw in the
//! first place: a camera JPEG has a tone curve, a white balance and sharpening
//! baked in, so feeding one to a film simulator means simulating film on an
//! image that has already been developed.

#![forbid(unsafe_code)]

use std::path::Path;

use kallotype_io::Image;
use rawler::Orientation;
use rawler::decoders::RawDecodeParams;
use rawler::imgop::develop::{Intermediate, ProcessingStep, RawDevelop};
use rawler::rawsource::RawSource;

/// File extensions this crate claims.
///
/// The list is the set of formats `rawler` decodes, using the extensions those
/// cameras actually write. It exists so the CLI can decide whether a file is a
/// raw by name before trying anything expensive.
pub const EXTENSIONS: &[&str] = &[
    "3fr", "ari", "arw", "cr2", "cr3", "crw", "dcr", "dcs", "dng", "erf", "iiq", "kdc", "mef",
    "mos", "mrw", "nef", "nkd", "nrw", "orf", "pef", "qtk", "raf", "raw", "rw2", "srw", "tfr",
    "x3f",
];

/// Whether a path looks like a camera raw by its extension.
///
/// Case-insensitive, and the file need not exist — this is a routing decision,
/// not a check.
#[must_use]
pub fn handles(path: impl AsRef<Path>) -> bool {
    path.as_ref()
        .extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| {
            let lower = extension.to_ascii_lowercase();
            EXTENSIONS.contains(&lower.as_str())
        })
}

/// Things that can go wrong decoding a raw file.
#[derive(Debug)]
pub enum RawError {
    /// The decoder could not open the file.
    Decode(rawler::RawlerError),
    /// The camera writes four colour channels, which this pipeline does not
    /// demosaic.
    FourColour {
        /// The camera, as the file names it.
        model: String,
    },
    /// The decoded pixels did not match the declared dimensions.
    Buffer,
}

impl std::fmt::Display for RawError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Decode(error) => write!(f, "raw decode failed: {error}"),
            Self::FourColour { model } => write!(
                f,
                "{model}: four-colour sensor, which this decoder does not demosaic"
            ),
            Self::Buffer => write!(f, "decoded pixel count does not match the image size"),
        }
    }
}

impl std::error::Error for RawError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Decode(error) => Some(error),
            Self::FourColour { .. } | Self::Buffer => None,
        }
    }
}

/// Decode a camera raw file to scene-referred linear sRGB.
///
/// The steps are the ones a raw developer takes and no more:
///
/// * `Rescale` — black level off, white level to one;
/// * `Demosaic` — the mosaic becomes three channels per pixel. `rawler` picks
///   the right kernel for the sensor: Bayer, or X-Trans for Fujifilm;
/// * `CropActiveArea` — the masked border off;
/// * `WhiteBalance` — the as-shot coefficients in the file;
/// * `Calibrate` — the camera's own colour matrix to sRGB primaries.
///
/// `SRgb` is deliberately **not** applied. The renderer wants linear light;
/// applying the sRGB transfer curve here would put back exactly the tone
/// mapping that reading raw is meant to avoid.
///
/// The file's Exif orientation is applied last, after the develop: the sensor is
/// read the way it lies, and a camera held on its side writes a landscape
/// mosaic with a tag saying which way up it was. The turn is a permutation of
/// whole pixels, so nothing is resampled a second time.
pub fn load(path: impl AsRef<Path>) -> Result<Image, RawError> {
    let path = path.as_ref();
    // One file, read once: the decoder is asked for the metadata and then for
    // the mosaic, because `rawler` keeps them apart and the orientation is only
    // in the first.
    let source = RawSource::new(path).map_err(|error| {
        RawError::Decode(rawler::RawlerError::with_io_error("opening", path, error))
    })?;
    let params = RawDecodeParams::default();
    let orientation = orientation(path, &source);
    let raw = rawler::decode(&source, &params).map_err(RawError::Decode)?;
    let developed = RawDevelop::new_with(&[
        ProcessingStep::Rescale,
        ProcessingStep::Demosaic,
        ProcessingStep::CropActiveArea,
        ProcessingStep::WhiteBalance,
        ProcessingStep::Calibrate,
    ])
    .develop_intermediate(&raw)
    .map_err(RawError::Decode)?;

    let rgb = match developed {
        Intermediate::ThreeColor(image) => image,
        Intermediate::Monochrome(_) | Intermediate::FourColor(_) => {
            return Err(RawError::FourColour {
                model: format!("{} {}", raw.clean_make, raw.clean_model),
            });
        }
    };

    let (width, height) = (rgb.width, rgb.height);
    if width == 0 || height == 0 || rgb.pixels().len() != width * height {
        return Err(RawError::Buffer);
    }
    let pixels = rgb
        .pixels()
        .iter()
        .map(|pixel| {
            [
                f64::from(pixel[0].max(0.0)),
                f64::from(pixel[1].max(0.0)),
                f64::from(pixel[2].max(0.0)),
            ]
        })
        .collect();

    let mut image = Image {
        width: u32::try_from(width).map_err(|_| RawError::Buffer)?,
        height: u32::try_from(height).map_err(|_| RawError::Buffer)?,
        pixels,
    };
    turn(&mut image, orientation);
    Ok(image)
}

/// How the camera was held, from the file's own Exif.
///
/// `rawler` hands over the sensor the way it lies: the decoders for the big
/// camera formats leave the orientation tag in the metadata and do not carry it
/// through to the image, so it is asked for separately. The answer is
/// best-effort — a file whose metadata cannot be read is still a file, and the
/// picture is worth more than the turn — and Sigma's X3F is skipped, because
/// the only metadata path `rawler` has for it is `todo!()`, and a panic is not
/// an orientation.
fn orientation(path: &Path, source: &RawSource) -> Orientation {
    let sigma = path
        .extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| extension.eq_ignore_ascii_case("x3f"));
    if sigma {
        return Orientation::Normal;
    }
    let Ok(decoder) = rawler::get_decoder(source) else {
        return Orientation::Normal;
    };
    let Ok(metadata) = decoder.raw_metadata(source, &RawDecodeParams::default()) else {
        return Orientation::Normal;
    };
    metadata
        .exif
        .orientation
        .map_or(Orientation::Normal, Orientation::from_u16)
}

/// Turn and flip the decoded picture to the way the camera was held.
///
/// The eight cases of Exif's orientation tag, and every one of them is a
/// permutation of whole pixels: nothing is resampled. A raw is light, and light
/// does not want interpolating twice.
fn turn(image: &mut Image, orientation: Orientation) {
    let (swap, horizontal, vertical) = orientation.to_flips();
    // The order `rawler` documents: the mirrors first, the transpose last.
    if horizontal {
        mirror(image, true);
    }
    if vertical {
        mirror(image, false);
    }
    if swap {
        transpose(image);
    }
}

/// Mirror the picture across its centre: left to right, or top to bottom.
fn mirror(image: &mut Image, horizontal: bool) {
    let width = image.width as usize;
    let height = image.height as usize;
    if horizontal {
        for row in 0..height {
            image.pixels[row * width..(row + 1) * width].reverse();
        }
    } else {
        for row in 0..height / 2 {
            let top = row * width;
            let bottom = (height - 1 - row) * width;
            for column in 0..width {
                image.pixels.swap(top + column, bottom + column);
            }
        }
    }
}

/// Turn the picture on its side: the rows become the columns.
fn transpose(image: &mut Image) {
    let width = image.width as usize;
    let height = image.height as usize;
    let mut pixels = vec![[0.0f64; 3]; width * height];
    for row in 0..height {
        for column in 0..width {
            pixels[column * height + row] = image.pixels[row * width + column];
        }
    }
    image.width = height as u32;
    image.height = width as u32;
    image.pixels = pixels;
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every turn the tag can ask for, as a permutation of whole pixels.
    #[test]
    fn the_orientation_is_a_turn_of_whole_pixels() {
        // Three wide and two tall, each pixel's index for a value: a portrait
        // frame is that picture with the camera on its side.
        let cases: &[(Orientation, (u32, u32), [f64; 6])] = &[
            (Orientation::Normal, (3, 2), [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]),
            (
                Orientation::HorizontalFlip,
                (3, 2),
                [2.0, 1.0, 0.0, 5.0, 4.0, 3.0],
            ),
            (
                Orientation::Rotate180,
                (3, 2),
                [5.0, 4.0, 3.0, 2.0, 1.0, 0.0],
            ),
            (
                Orientation::VerticalFlip,
                (3, 2),
                [3.0, 4.0, 5.0, 0.0, 1.0, 2.0],
            ),
            (
                Orientation::Transpose,
                (2, 3),
                [0.0, 3.0, 1.0, 4.0, 2.0, 5.0],
            ),
            (
                Orientation::Rotate90,
                (2, 3),
                [3.0, 0.0, 4.0, 1.0, 5.0, 2.0],
            ),
            (
                Orientation::Transverse,
                (2, 3),
                [5.0, 2.0, 4.0, 1.0, 3.0, 0.0],
            ),
            (
                Orientation::Rotate270,
                (2, 3),
                [2.0, 5.0, 1.0, 4.0, 0.0, 3.0],
            ),
        ];
        for &(orientation, (width, height), expected) in cases {
            let mut image = Image {
                width: 3,
                height: 2,
                pixels: (0..6)
                    .map(|index| {
                        let value = index as f64;
                        [value; 3]
                    })
                    .collect(),
            };
            turn(&mut image, orientation);
            assert_eq!(
                (image.width, image.height),
                (width, height),
                "{orientation:?}"
            );
            let turned: Vec<f64> = image.pixels.iter().map(|pixel| pixel[0]).collect();
            assert_eq!(turned, expected, "{orientation:?}");
        }
    }

    #[test]
    fn the_extensions_are_recognised_in_any_case() {
        assert!(handles("DSC03315.ARW"));
        assert!(handles("DSCF0989.RAF"));
        assert!(handles("shot.cr3"));
        assert!(!handles("portrait.jpg"));
        assert!(!handles("no-extension"));
    }

    /// Decode a real raw when one is pointed at.
    ///
    /// The fixtures are camera files, they are large, and they are not
    /// redistributable, so none of them live in the repository. Set
    /// `KALLOTYPE_RAW_FIXTURE` to one to run this.
    #[test]
    fn a_raw_file_decodes_to_linear_pixels() {
        let Ok(path) = std::env::var("KALLOTYPE_RAW_FIXTURE") else {
            return;
        };
        let image = load(&path).expect("decode");
        assert!(image.width > 0 && image.height > 0);
        assert_eq!(
            image.pixels.len(),
            image.width as usize * image.height as usize
        );
        let mean: f64 = image.pixels.iter().map(|p| p[0]).sum::<f64>() / image.pixels.len() as f64;
        // Scene-referred linear light: a normally exposed frame sits near 18 %
        // grey in its green channel. This is a sanity check on the pipeline
        // rather than a measurement, hence the generous window.
        assert!((0.01..1.0).contains(&mean), "implausible mean {mean}");
        assert!(
            image.pixels.iter().all(|p| p.iter().all(|c| c.is_finite())),
            "non-finite pixel"
        );
    }

    /// A fixture the camera stored on its side comes out the way up.
    ///
    /// Set `KALLOTYPE_RAW_FIXTURE_TURNED` to a raw whose orientation tag is 6
    /// or 8 — a copy of a fixture with that one tag rewritten is enough — and
    /// the picture must be taller than it is wide.
    #[test]
    fn a_turned_fixture_is_read_the_way_up() {
        let Ok(path) = std::env::var("KALLOTYPE_RAW_FIXTURE_TURNED") else {
            return;
        };
        let image = load(&path).expect("decode");
        assert!(
            image.height > image.width,
            "a file the camera held on its side must come out portrait: {}x{}",
            image.width,
            image.height
        );
    }
}
