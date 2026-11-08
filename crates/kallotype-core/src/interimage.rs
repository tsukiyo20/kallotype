//! The cyan-sensitive layer's inhibitor, acting on the cyan dye — ADR 0018.
//!
//! Fuji's fourth layer is not a second cyan-forming emulsion: the 1989 REALA
//! paper describes it as sensitive to cyan light (ca. 470–540 nm) and releasing
//! **development inhibitors** in proportion to exposure, which pull back the
//! red-sensitive layer and approximate the negative lobe of the colour matching
//! functions. A layer like that forms no density of its own, so a model built
//! out of two dye curves cannot hold it — which is what PRO 400H's sheet said,
//! loudly, by refusing to split its cyan curve.
//!
//! ## What is modelled
//!
//! The layer's inhibitor release is taken to be proportional to the light it
//! absorbed, and it is compared against the **frame's own mean**. That
//! subtraction is the whole model rather than a convenience:
//!
//! - the characteristic curve on the data sheet was measured with a neutral
//!   wedge, which exposes this layer uniformly, so whatever the uniform
//!   inhibition does is already inside the curve;
//! - a model that added it again would darken every frame by a number nobody
//!   measured;
//! - and a uniform frame therefore has to come out unchanged, which is the
//!   invariant the tests hold it to.
//!
//! What is left is the local part: where the layer sees more cyan light than
//! the frame average, the cyan dye is suppressed; where it sees less, it is let
//! through. The inhibitor diffuses a short way, which is what makes the effect
//! an edge effect and not a per-pixel gain.
//!
//! ## What is not measured
//!
//! The strength and the diffusion length are placeholders, the same way the
//! halation numbers are. A frame rendered with them is a demonstration of a
//! mechanism, not a prediction for this stock. Measuring them needs patches
//! that are not uniform — a step or a sinusoid seen through the right filter —
//! and nothing in a data sheet is.

use crate::psf::gaussian_blur;

/// A cyan-sensitive inhibitor layer for one image.
#[derive(Debug, Clone, Copy)]
pub struct InterImage {
    /// How much cyan density the maximum local excess of exposure takes away,
    /// as a fraction at full deviation.
    pub gain: f64,
    /// How far the inhibitor diffuses on the film, in micrometres.
    pub sigma_um: f64,
    /// Size of one pixel on the film, in micrometres across.
    pub pixel_um: f64,
}

impl InterImage {
    /// Placeholder values: a 12 % swing and the same diffusion length the DIR
    /// couplers use. Neither is measured for any stock.
    #[must_use]
    pub fn typical(pixel_um: f64) -> Self {
        Self {
            gain: 0.12,
            sigma_um: 20.0,
            pixel_um,
        }
    }

    /// Whether this would change anything.
    #[must_use]
    pub fn is_noop(&self) -> bool {
        self.gain <= 0.0
    }

    /// Apply the layer's inhibition to a buffer of densities, in place.
    ///
    /// `light` is the fourth layer's relative exposure per pixel — the linear
    /// quantity, not its logarithm, because the release is a fraction of the
    /// light absorbed and the log would make the mean meaningless.
    pub fn apply(&self, density: &mut [[f64; 3]], light: &[f64], width: usize, height: usize) {
        if self.is_noop() || width == 0 || height == 0 {
            return;
        }
        let pixels = (width * height).min(density.len()).min(light.len());
        let height = pixels / width;
        if height == 0 {
            return;
        }

        let mean = light[..pixels].iter().sum::<f64>() / pixels as f64;
        // A frame with no light in the layer has no average to deviate from,
        // and a non-finite one is a bug upstream rather than a dark frame.
        if !mean.is_finite() || mean <= 0.0 {
            return;
        }

        // The inhibitor diffuses before it acts, so a single bright pixel
        // suppresses its neighbours and not only itself.
        let sigma_px = self.sigma_um / self.pixel_um.max(1e-9);
        let diffused = gaussian_blur(&light[..pixels], width, height, sigma_px);

        for (index, pixel) in density[..pixels].iter_mut().enumerate() {
            // Deviations from the frame's mean, in units of it: -1 where the
            // layer saw no light at all, +k where it saw k times the average.
            let deviation = diffused[index] / mean - 1.0;
            // Only the cyan dye: this inhibitor's target is the red-sensitive
            // layer, which is the one that forms cyan.
            pixel[0] = (pixel[0] * (1.0 - self.gain * deviation)).max(0.0);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn light_from(values: impl Fn(usize) -> f64, count: usize) -> Vec<f64> {
        (0..count).map(values).collect()
    }

    /// The invariant the model is built on: a uniform frame comes out
    /// unchanged, because the uniform inhibition is already in the curve.
    #[test]
    fn a_uniform_frame_is_untouched() {
        let stage = InterImage::typical(6.0);
        let mut density = vec![[1.0, 0.8, 0.6]; 64];
        let expected = density.clone();
        stage.apply(&mut density, &light_from(|_| 3.7, 64), 8, 8);
        for (left, right) in density.iter().zip(&expected) {
            assert!((left[0] - right[0]).abs() < 1e-12, "{left:?} vs {right:?}");
        }
    }

    /// A step: cyan is taken away where the layer saw more light than the frame
    /// average, and given back where it saw less. The two halves balance, which
    /// is what makes this an inter-image effect rather than a gain.
    #[test]
    fn a_step_takes_cyan_from_the_bright_side() {
        let stage = InterImage {
            gain: 0.12,
            sigma_um: 0.01,
            pixel_um: 1.0,
        };
        let mut density = vec![[1.0, 1.0, 1.0]; 16];
        let light = light_from(|index| if index % 16 < 8 { 0.0 } else { 4.0 }, 16);
        stage.apply(&mut density, &light, 16, 1);
        let dark = density[0][0];
        let bright = density[15][0];
        assert!(
            bright < dark,
            "bright {bright:.4} should be below dark {dark:.4}"
        );
        assert!((dark - 1.0).abs() > 0.05 && (1.0 - bright).abs() > 0.05);
        // The other two dyes are not this layer's business.
        assert_eq!([density[0][1], density[0][2]], [1.0, 1.0]);
        let mean: f64 = density.iter().map(|pixel| pixel[0]).sum::<f64>() / 16.0;
        assert!((mean - 1.0).abs() < 1e-12, "mean {mean}");
    }

    /// A frame with no light anywhere is the uniform case, not a division by
    /// zero: the layer is dark, so it inhibits nothing below the average and
    /// there is no average to be below.
    #[test]
    fn a_dark_frame_is_untouched() {
        let stage = InterImage::typical(6.0);
        let mut density = vec![[0.5, 0.5, 0.5]; 4];
        stage.apply(&mut density, &[0.0; 4], 2, 2);
        assert_eq!(density[0], [0.5, 0.5, 0.5]);
    }

    /// A zero gain is a no-op, so a stock can carry the layer and a flag can
    /// turn the mechanism off without a second code path.
    #[test]
    fn a_zero_gain_changes_nothing() {
        let stage = InterImage {
            gain: 0.0,
            ..InterImage::typical(6.0)
        };
        assert!(stage.is_noop());
        let mut density = vec![[1.0, 1.0, 1.0]; 8];
        stage.apply(&mut density, &light_from(|index| index as f64, 8), 8, 1);
        assert_eq!(density[3], [1.0, 1.0, 1.0]);
    }
}
