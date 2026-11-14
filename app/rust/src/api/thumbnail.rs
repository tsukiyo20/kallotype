//! The wall's copy of a print.
//!
//! The gallery and the rack do not need a 26-megapixel file; they need the
//! paper at 512 pixels. Flutter's decoder can be asked for a target width, but
//! a PNG is still decoded at its own size before it is scaled, which leaves a
//! large buffer behind for every print on a wall. The model's image reader
//! already knows how to decode at camera sizes; this is the one place that
//! turns one into a small file and lets the buffer go.

use std::path::Path;

use image::{DynamicImage, GenericImageView as _, ImageDecoder as _, ImageFormat, ImageReader};

/// Write a thumbnail of [input] to [output], no wider than [width].
///
/// The shape is kept. A source narrower than [width] is not enlarged: the
/// gallery is a wall, not an upscaler. The result is PNG because it is a print
/// on paper and the cache may keep it for a long time.
pub fn make_thumbnail(input: String, output: String, width: u32) -> Result<(), String> {
    if width == 0 {
        return Err("a thumbnail needs a width".to_owned());
    }
    let reader = ImageReader::open(&input)
        .map_err(|error| error.to_string())?
        .with_guessed_format()
        .map_err(|error| error.to_string())?;

    // The same camera-sized limits as the model's reader. The default is tuned
    // for icons and refuses a full-frame photograph.
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(65_535);
    limits.max_image_height = Some(65_535);
    limits.max_alloc = Some(512 * 1024 * 1024);
    let mut decoder = reader.into_decoder().map_err(|error| error.to_string())?;
    let orientation = decoder.orientation().map_err(|error| error.to_string())?;
    limits
        .reserve(decoder.total_bytes())
        .map_err(|error| error.to_string())?;
    decoder
        .set_limits(limits)
        .map_err(|error| error.to_string())?;
    let mut image = DynamicImage::from_decoder(decoder).map_err(|error| error.to_string())?;
    image.apply_orientation(orientation);

    let (source_width, source_height) = image.dimensions();
    if source_width == 0 || source_height == 0 {
        return Err("the print has no pixels".to_owned());
    }
    let target_width = width.min(source_width);
    let target_height = ((u64::from(source_height) * u64::from(target_width)
        + u64::from(source_width) / 2)
        / u64::from(source_width))
    .max(1) as u32;
    let thumbnail = image.thumbnail(target_width, target_height);
    thumbnail
        .save_with_format(Path::new(&output), ImageFormat::Png)
        .map_err(|error| error.to_string())
}
