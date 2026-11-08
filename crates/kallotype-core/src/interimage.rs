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
//! The release is proportional to the light the layer absorbed, and it is
//! compared against **the light that same pixel absorbed**: where the
//! neighbourhood released more than this pixel did, this pixel's cyan is
//! suppressed; where the inhibitor diffused away to brighter neighbours, it is
//! let through.
//!
//! That baseline is the whole model, and it is a stronger statement than "the
//! effect is local". The characteristic curve on the data sheet was measured
//! with a neutral wedge, which exposes every patch uniformly, so a patch's
//! uniform inhibition is *already inside the curve* — at every level, not just
//! at the frame's average. Comparing against the frame mean instead would make
//! a patch's colour depend on what else is in the frame, which is not an
//! inter-image effect; comparing against the pixel's own light makes a flat
//! region come out unchanged however bright it is, and leaves only the
//! structure: edges, fine detail, the transition across a boundary.
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

        // A scale for the floor below, and the answer to "is there any light".
        let mean = light[..pixels].iter().sum::<f64>() / pixels as f64;
        if !mean.is_finite() || mean <= 0.0 {
            return;
        }
        // The inhibitor diffuses before it acts, so a single bright pixel
        // suppresses its neighbours and not only itself.
        let sigma_px = self.sigma_um / self.pixel_um.max(1e-9);
        let diffused = gaussian_blur(&light[..pixels], width, height, sigma_px);

        for (index, pixel) in density[..pixels].iter_mut().enumerate() {
            // How much more (or less) inhibitor this pixel's neighbourhood made
            // than the uniform case the curve was measured with. Zero on a flat
            // region at any brightness; bounded, because a layer cannot be
            // inhibited by more than "all of it". A pixel that saw nothing next
            // to one that saw a great deal is the limit case, and it is written
            // out rather than approached with a floor so that a flat shadow is
            // exactly unchanged.
            let local = light[index];
            let deviation = if local > 0.0 {
                (diffused[index] / local - 1.0).clamp(-1.0, 1.0)
            } else if diffused[index] > 0.0 {
                1.0
            } else {
                0.0
            };
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

    /// A step. The bright side's inhibitor diffuses into the dark side, so the
    /// shadow loses cyan; the bright side keeps less of its own inhibitor than a
    /// flat patch would, so it gains. Both are bounded by the gain, and both
    /// fall back to nothing within a few diffusion lengths.
    #[test]
    fn a_step_takes_cyan_off_the_shadow_side() {
        let stage = InterImage {
            gain: 0.12,
            sigma_um: 3.0,
            pixel_um: 1.0,
        };
        let mut density = vec![[1.0, 1.0, 1.0]; 64];
        let light = light_from(|index| if index < 32 { 0.0 } else { 4.0 }, 64);
        stage.apply(&mut density, &light, 64, 1);

        let shadow = density[31][0];
        let bright = density[32][0];
        assert!(shadow < 0.93, "the shadow kept the inhibitor: {shadow:.4}");
        assert!(
            bright > 1.01,
            "the bright side lost instead of gaining: {bright:.4}"
        );
        // Bounded by the gain, in both directions.
        assert!(
            density
                .iter()
                .all(|pixel| (0.88..=1.12).contains(&pixel[0]))
        );
        // Far from the boundary both sides are the flat case again.
        assert!((density[0][0] - 1.0).abs() < 1e-9, "{:?}", density[0]);
        assert!((density[63][0] - 1.0).abs() < 1e-9, "{:?}", density[63]);
        // The other two dyes are not this layer's business.
        assert_eq!([density[31][1], density[31][2]], [1.0, 1.0]);
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
