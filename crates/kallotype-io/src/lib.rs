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
    let mut reader = reader
        .with_guessed_format()
        .map_err(image::ImageError::IoError)?;
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

/// Resample an image to a width, keeping its shape.
///
/// An area average and not a bilinear tap: shrinking is the case that matters
/// here — a camera file meeting a window — and a tap at a scale of five skips
/// four pixels in every five. Averaging what each destination pixel covers is
/// the filter that answers the question the pixel asks: how much light was in
/// this patch of the frame.
///
/// The pixels are linear light, so they average the way light does. Asking for
/// a width the image already has, or a larger one, returns it unchanged: this
/// is a resize down, and nothing here invents detail.
#[must_use]
pub fn resize_to_width(image: &Image, width: u32) -> Image {
    if width == 0 || image.width == 0 || image.height == 0 || width >= image.width {
        return image.clone();
    }
    let scale = f64::from(image.width) / f64::from(width);
    let height = ((f64::from(image.height) / scale).round() as u32).max(1);
    let mut pixels = vec![[0.0f64; 3]; (width * height) as usize];

    for y in 0..height {
        let top = f64::from(y) * f64::from(image.height) / f64::from(height);
        let bottom = f64::from(y + 1) * f64::from(image.height) / f64::from(height);
        let y0 = (top.floor() as u32).min(image.height - 1);
        let y1 = (bottom.ceil() as u32).clamp(y0 + 1, image.height);
        for x in 0..width {
            let left = f64::from(x) * f64::from(image.width) / f64::from(width);
            let right = f64::from(x + 1) * f64::from(image.width) / f64::from(width);
            let x0 = (left.floor() as u32).min(image.width - 1);
            let x1 = (right.ceil() as u32).clamp(x0 + 1, image.width);

            let mut sum = [0.0f64; 3];
            let mut count = 0.0f64;
            for source_y in y0..y1 {
                let row = (source_y * image.width) as usize;
                for source_x in x0..x1 {
                    let pixel = image.pixels[row + source_x as usize];
                    sum[0] += pixel[0];
                    sum[1] += pixel[1];
                    sum[2] += pixel[2];
                    count += 1.0;
                }
            }
            pixels[(y * width + x) as usize] = [sum[0] / count, sum[1] / count, sum[2] / count];
        }
    }

    Image {
        width,
        height,
        pixels,
    }
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
    fn a_resize_keeps_the_shape_and_the_light() {
        let image = Image {
            width: 6,
            height: 4,
            pixels: vec![[0.5, 0.25, 1.0]; 24],
        };
        let half = resize_to_width(&image, 3);
        assert_eq!((half.width, half.height), (3, 2));
        assert_eq!(half.pixels.len(), 6);
        for pixel in &half.pixels {
            assert!((pixel[0] - 0.5).abs() < 1e-9);
            assert!((pixel[1] - 0.25).abs() < 1e-9);
            assert!((pixel[2] - 1.0).abs() < 1e-9);
        }
    }

    #[test]
    fn a_resize_down_averages_and_a_resize_up_does_nothing() {
        let image = Image {
            width: 4,
            height: 2,
            pixels: [[[0.0, 0.0, 0.0], [1.0, 1.0, 1.0], [0.0, 0.0, 0.0], [1.0, 1.0, 1.0]]; 2]
                .concat(),
        };
        let half = resize_to_width(&image, 2);
        // Two columns of black and white averaged into one of mid grey, twice.
        for pixel in &half.pixels {
            assert!((pixel[0] - 0.5).abs() < 1e-9, "{pixel:?}");
        }
        let same = resize_to_width(&image, 4);
        assert_eq!((same.width, same.height), (4, 2));
        assert_eq!(same.pixels, image.pixels);
        let bigger = resize_to_width(&image, 9);
        assert_eq!((bigger.width, bigger.height), (4, 2));
    }

    #[test]
    fn encoding_flag_round_trips_mid_grey() {
        let linear = srgb_to_linear(0.5);
        assert!((linear_to_srgb(linear) - 0.5).abs() < 1e-9);
    }
}
