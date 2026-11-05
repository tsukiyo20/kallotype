//! Transfer functions.
//!
//! Phase 0 works in a single, unnamed RGB space: linear light in, linear light
//! out. Primaries are not part of the contract yet, so the only thing needed
//! here is the sRGB transfer function (IEC 61966-2-1), used to decode ordinary
//! 8/16-bit image files on the way in and to encode them on the way out.

/// Threshold below which the sRGB decode is linear (IEC 61966-2-1).
const SRGB_DECODE_KNEE: f64 = 0.040_45;
/// Threshold below which the sRGB encode is linear (IEC 61966-2-1).
const SRGB_ENCODE_KNEE: f64 = 0.003_130_8;

/// Decode one sRGB-encoded channel to linear light.
#[inline]
#[must_use]
pub fn srgb_to_linear(v: f64) -> f64 {
    let v = v.clamp(0.0, 1.0);
    if v <= SRGB_DECODE_KNEE {
        v / 12.92
    } else {
        ((v + 0.055) / 1.055).powf(2.4)
    }
}

/// Encode one linear-light channel to sRGB.
#[inline]
#[must_use]
pub fn linear_to_srgb(v: f64) -> f64 {
    let v = v.max(0.0);
    if v <= SRGB_ENCODE_KNEE {
        v * 12.92
    } else {
        1.055 * v.powf(1.0 / 2.4) - 0.055
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_is_stable() {
        for i in 0..=100 {
            let v = f64::from(i) / 100.0;
            let round_trip = linear_to_srgb(srgb_to_linear(v));
            assert!((round_trip - v).abs() < 1e-9, "{v} -> {round_trip}");
        }
    }

    #[test]
    fn mid_grey_is_about_eighteen_percent() {
        // sRGB 0.5 decodes close to 0.2140; 18% grey encodes close to 0.4613.
        assert!((linear_to_srgb(0.18) - 0.4613).abs() < 1e-3);
    }
}
