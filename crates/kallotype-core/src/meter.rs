//! Metering: where a frame's exposure is, and how far it is from where the film
//! expects it.
//!
//! The input is a linear-light image on the scale "1.0 is white". That scale is
//! enough for a frame that is already exposed the way the model assumes — 18 %
//! grey is at `log10(0.18)` by definition — but not for one whose scale is
//! unknown, which is most inputs: a camera RAW developed to a float TIFF is
//! normalised to its own white point, and how much light that white point
//! corresponds to is not in the file.
//!
//! The oldest rule in photography recovers the missing scale from the frame
//! itself: the average scene reflects 18 % of the light falling on it. An
//! averaging exposure meter and a laboratory's average printer both rest on
//! that assumption; this module is the same rule, solved in closed form
//! instead of by a test strip.
//!
//! # What it does not do
//!
//! It is an *averaging* meter, not an evaluative one. A frame whose average is
//! not 18 % — a night street, a snowfield, a snowfield at night — is metered to
//! 18 % anyway, exactly as the hardware would. That is a property of the rule,
//! not a defect to be tuned away: pass a fixed `--ev` when the scene's key
//! differs from the average, which is what a photographer's exposure
//! compensation dial is for.

use crate::pipeline::mid_grey_log_e;

/// The luminance weights of Rec. 709, which is the space the input is in.
///
/// The channels are *not* averaged equally: pure red is 21 % of white's
/// luminance, not 33 %, and a frame of redness is not a bright frame.
const LUMA: [f64; 3] = [0.2126, 0.7152, 0.0722];

/// What an averaging meter reads of a frame, and the offset that follows.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Metering {
    /// Mean luminance of the frame, in linear light.
    ///
    /// Zero for a frame with no light at all, and for an empty one.
    pub key: f64,
    /// Exposure offset in stops that puts `key` on mid grey.
    ///
    /// Zero when the frame is already mid grey, and zero when it carries no
    /// light to meter: a black frame has no exposure to recover, so the meter
    /// says nothing rather than everything.
    pub ev: f64,
}

impl Metering {
    /// Meter a row-major frame.
    ///
    /// The mean is taken over every pixel and weighed by luminance. It is
    /// arithmetic in linear light, not in log: the average printer integrates
    /// transmittance, and a frame that is half black and half white integrates
    /// to 0.5, not to the geometric mean.
    #[must_use]
    pub fn of(pixels: &[[f64; 3]]) -> Self {
        if pixels.is_empty() {
            return Self { key: 0.0, ev: 0.0 };
        }

        let mut sum = 0.0;
        for pixel in pixels {
            // A decoded image should not be negative or NaN, but a meter is the
            // wrong place to discover it: `max` clamps the first and turns the
            // second into black, and the finite check keeps an infinity out.
            let value = LUMA[0] * pixel[0].max(0.0)
                + LUMA[1] * pixel[1].max(0.0)
                + LUMA[2] * pixel[2].max(0.0);
            if value.is_finite() {
                sum += value;
            }
        }
        let key = sum / pixels.len() as f64;

        Self {
            key,
            ev: offset_for(key),
        }
    }
}

/// The offset in stops from a frame's key to the film's mid-grey exposure.
///
/// Defined as the solve `key · 2^ev = 0.18`, written in the module's own
/// currency of decades instead of duplicating the constant.
#[must_use]
pub fn offset_for(key: f64) -> f64 {
    if !key.is_finite() || key <= 0.0 {
        return 0.0;
    }
    (mid_grey_log_e() - key.log10()) / 2.0_f64.log10()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_frame_of_mid_grey_needs_no_offset() {
        let metered = Metering::of(&[[0.18; 3]; 64]);
        assert!((metered.key - 0.18).abs() < 1e-12, "{}", metered.key);
        assert!(metered.ev.abs() < 1e-9, "{}", metered.ev);
    }

    #[test]
    fn a_frame_two_stops_dark_is_lifted_by_two() {
        // A quarter of 18 % is two stops down.
        let metered = Metering::of(&[[0.045; 3]; 64]);
        assert!((metered.ev - 2.0).abs() < 1e-9, "{}", metered.ev);
    }

    #[test]
    fn a_frame_with_no_light_gets_no_offset() {
        // Nothing to meter: an infinite offset would be a claim about a frame
        // that carries no information.
        let metered = Metering::of(&[[0.0; 3]; 16]);
        assert_eq!(metered.key, 0.0);
        assert_eq!(metered.ev, 0.0);
    }

    #[test]
    fn an_empty_frame_is_not_a_division_by_zero() {
        assert_eq!(Metering::of(&[]), Metering { key: 0.0, ev: 0.0 });
    }

    #[test]
    fn the_meter_weighs_the_channels_as_luminance() {
        // Pure red is 21 % of white to the eye. A meter that averaged the three
        // channels would call it 33 % and expose it two-thirds of a stop down.
        let metered = Metering::of(&[[1.0, 0.0, 0.0]]);
        assert!((metered.key - LUMA[0]).abs() < 1e-12, "{}", metered.key);
    }

    #[test]
    fn the_offset_lands_the_key_on_mid_grey() {
        // The definition of the solve, over the range a frame can occupy.
        for key in [1e-3, 0.02, 0.18, 0.9] {
            let metered = Metering::of(&[[key; 3]]);
            let landed = key * 2.0_f64.powf(metered.ev);
            assert!((landed - 0.18).abs() < 1e-9, "{key} landed at {landed}");
        }
    }

    #[test]
    fn the_mean_is_arithmetic_not_geometric() {
        // Half black and half white: the average printer integrates light, so
        // this frame's key is 0.5 — two stops above mid grey — not the
        // geometric mean of nothing.
        let mut pixels = vec![[0.0; 3]; 8];
        pixels.extend(std::iter::repeat_n([1.0; 3], 8));
        let metered = Metering::of(&pixels);
        assert!((metered.key - 0.5).abs() < 1e-12, "{}", metered.key);
        assert!((metered.ev + 1.4739).abs() < 1e-3, "{}", metered.ev);
    }

    #[test]
    fn negatives_and_nonsense_do_not_poison_the_mean() {
        let mut pixels = vec![[0.18; 3]; 4];
        pixels.push([-1.0, -1.0, -1.0]);
        pixels.push([f64::NAN, f64::NAN, f64::NAN]);
        let metered = Metering::of(&pixels);
        // The negative clamps to black and the NaN is dropped, so the mean is
        // four mid-grey pixels over six: the meter does not invent light.
        assert!((metered.key - 0.12).abs() < 1e-12, "{}", metered.key);
    }
}
