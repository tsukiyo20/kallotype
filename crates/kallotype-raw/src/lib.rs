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
use rawler::imgop::develop::{Intermediate, ProcessingStep, RawDevelop};

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
pub fn load(path: impl AsRef<Path>) -> Result<Image, RawError> {
    let path = path.as_ref();
    let raw = rawler::decode_file(path).map_err(RawError::Decode)?;
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

    Ok(Image {
        width: u32::try_from(width).map_err(|_| RawError::Buffer)?,
        height: u32::try_from(height).map_err(|_| RawError::Buffer)?,
        pixels,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

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
}
