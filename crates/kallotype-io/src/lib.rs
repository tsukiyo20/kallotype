//! Image loading and saving.
//!
//! The core crate knows nothing about files. This crate is the only place that
//! touches a decoder, which keeps the physics testable without fixtures and
//! makes it obvious where colour management will eventually enter.
//!
//! Files are read as 8/16-bit RGB (the common case: a camera export or a
//! screenshot) and interpreted according to [`InputEncoding`]. On the way out
//! everything is encoded back to sRGB.

#![forbid(unsafe_code)]

use std::path::Path;

use image::RgbImage;
use kallotype_core::{linear_to_srgb, srgb_to_linear};

/// How the values stored in the input file should be interpreted.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputEncoding {
    /// Ordinary display-referred sRGB (PNG, JPEG, most TIFFs). Decoded to linear.
    Srgb,
    /// Already linear light (a float TIFF/EXR exported from a RAW developer).
    /// Values are taken as they are.
    Linear,
}

/// A decoded image, held as linear-light `f64` RGB.
#[derive(Debug, Clone)]
pub struct Image {
    /// Width in pixels.
    pub width: u32,
    /// Height in pixels.
    pub height: u32,
    /// Row-major pixels, three channels, linear light.
    pub pixels: Vec<[f64; 3]>,
}

/// Things that can go wrong while reading or writing an image.
#[derive(Debug)]
pub enum IoError {
    /// The decoder rejected the file.
    Image(image::ImageError),
    /// The buffer length did not match the declared dimensions.
    Buffer,
}

impl std::fmt::Display for IoError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Image(error) => write!(f, "image error: {error}"),
            Self::Buffer => write!(
                f,
                "could not build an output buffer from the rendered pixels"
            ),
        }
    }
}

impl std::error::Error for IoError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Image(error) => Some(error),
            Self::Buffer => None,
        }
    }
}

impl From<image::ImageError> for IoError {
    fn from(error: image::ImageError) -> Self {
        Self::Image(error)
    }
}

/// Read an image from disk and return linear-light pixels.
///
/// The decoder's default limits are a decompression-bomb guard tuned for
/// thumbnails: a 33 MP 16-bit frame — one full-frame camera, unscaled — trips
/// them and is refused as "memory limit exceeded". A renderer whose job is to
/// eat camera files raises them to something a camera can actually produce and
/// leaves the guard in place rather than removing it.
pub fn load(path: impl AsRef<Path>, encoding: InputEncoding) -> Result<Image, IoError> {
    let reader = image::ImageReader::open(path).map_err(image::ImageError::IoError)?;
    let mut reader = reader.with_guessed_format().map_err(image::ImageError::IoError)?;
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(65_535);
    limits.max_image_height = Some(65_535);
    limits.max_alloc = Some(8 * 1024 * 1024 * 1024);
    reader.limits(limits);
    let dynamic = reader.decode()?;
    let rgb = dynamic.to_rgb32f();
    let (width, height) = rgb.dimensions();

    let mut pixels = Vec::with_capacity((width as usize) * (height as usize));
    for pixel in rgb.pixels() {
        let [r, g, b] = pixel.0;
        let mut out = [f64::from(r), f64::from(g), f64::from(b)];
        if encoding == InputEncoding::Srgb {
            for channel in &mut out {
                *channel = srgb_to_linear(*channel);
            }
        }
        pixels.push(out);
    }

    Ok(Image {
        width,
        height,
        pixels,
    })
}

/// Encode linear-light pixels to sRGB and write them to disk.
///
/// The container is chosen from the file extension, so `out.png` and
/// `out.tiff` both work.
pub fn save(path: impl AsRef<Path>, image: &Image) -> Result<(), IoError> {
    let mut buffer = Vec::with_capacity(image.pixels.len() * 3);
    for pixel in &image.pixels {
        for channel in pixel {
            let encoded = linear_to_srgb(*channel);
            buffer.push((encoded * 255.0).round().clamp(0.0, 255.0) as u8);
        }
    }

    let rgb = RgbImage::from_raw(image.width, image.height, buffer).ok_or(IoError::Buffer)?;
    rgb.save(path)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encoding_flag_round_trips_mid_grey() {
        let linear = srgb_to_linear(0.5);
        assert!((linear_to_srgb(linear) - 0.5).abs() < 1e-9);
    }
}
