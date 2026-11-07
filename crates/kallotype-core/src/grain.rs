//! Grain, as a particle process rather than as noise.
//!
//! A developed emulsion is a random arrangement of silver grains. A pixel is an
//! aperture over that arrangement, so its density is a *count* — how many grains
//! fell inside the aperture and developed — and a count has a variance.
//!
//! The model here is the standard one. At mean density `D` a fraction
//! `c = 1 − 10^(−D)` of the layer is covered by developed grains. A pixel of
//! area `A` µm² holds `N = n·A·c` of them, where `n` is the developed grain
//! density in grains per µm². A Poisson count of `N` events has a relative
//! standard deviation of `1/√N`, and density is `log10` of the count, so the
//! fluctuation in **log exposure** is
//!
//! ```text
//! σ_logE = 1 / (ln 10 · √N)
//! ```
//!
//! Putting the fluctuation on the exposure rather than on the density is what
//! makes the ends behave: the toe of the characteristic curve is flat, so noise
//! there produces almost no density, and the shoulder saturates, so a pixel
//! already at maximum density cannot get noisier. Applying noise to density
//! directly would have to special-case both ends, and would get them wrong.
//!
//! Two properties fall out for free:
//!
//! - **Selwyn granularity.** `σ ∝ 1/√A`, so rendering at twice the resolution
//!   gives √2 times the grain per pixel and the same graininess in the print.
//!   That is the empirical Selwyn law, and it is why `A` is a parameter rather
//!   than a constant.
//! - **Density dependence.** Grain is invisible in a blank frame and peaks where
//!   the curve is steepest, without either being written down as a rule.
//!
//! ## What is not modelled
//!
//! The grain density `n` is a placeholder, not a measurement: it is chosen so the
//! model reproduces an RMS granularity of about 0.005 at `D = 1` across a 48 µm
//! aperture, the order of magnitude the manufacturers publish for ISO 400–800
//! colour negative films. Pinning it against the film's own data sheet at two
//! apertures is the exit criterion for this phase.
//!
//! Development is not linked in yet. Grain clumping does grow with development —
//! the literature is clear about the direction and says little about the law —
//! but a made-up exponent is worse than an honest gap, so the relation waits for
//! a measurement.

/// The grain field of one image.
///
/// Positions are image pixels, so the same seed and the same crop render the
/// same grain; resizing the image changes the pixel area and therefore the
/// graininess, which is the physical statement rather than a bug.
#[derive(Debug, Clone)]
pub struct GrainField {
    /// Image width in pixels.
    pub width: usize,
    /// Image height in pixels.
    pub height: usize,
    /// Area of one pixel on the film, in square micrometres.
    pub pixel_area_um2: f64,
    /// Developed grains per square micrometre, one number per layer.
    pub grains_per_um2: [f64; 3],
    /// Seed: the grain is a fixture, not a different image every render.
    pub seed: u64,
}

impl GrainField {
    /// The default grain density per layer, in grains per µm².
    ///
    /// A placeholder: see the module documentation for what it reproduces and
    /// what would replace it.
    pub const DEFAULT_GRAINS_PER_UM2: f64 = 3.6;

    /// A field for an image `width × height` pixels covering `frame_mm` across.
    ///
    /// `frame_mm` is the width of the film frame the image represents — 36 for
    /// a 35 mm frame — so pixel size is `frame_mm / width` in millimetres.
    /// Square pixels are assumed.
    #[must_use]
    pub fn new(width: usize, height: usize, frame_mm: f64, seed: u64) -> Self {
        let pixel_mm = frame_mm.max(1e-9) / width.max(1) as f64;
        let pixel_um = pixel_mm * 1000.0;
        Self {
            width,
            height,
            pixel_area_um2: pixel_um * pixel_um,
            grains_per_um2: [Self::DEFAULT_GRAINS_PER_UM2; 3],
            seed,
        }
    }

    /// Standard deviation of the log-exposure fluctuation at mean `density`.
    ///
    /// The `+ 1` in the denominator is the empty aperture: a pixel with no
    /// developed grain in it is still a measurement, and the uncertainty of
    /// counting zero events is one event, not zero.
    #[must_use]
    pub fn sigma(&self, density: f64, channel: usize) -> f64 {
        let covered = 1.0 - 10.0_f64.powf(-density.max(0.0));
        let grains = self.grains_per_um2[channel].max(0.0) * self.pixel_area_um2 * covered;
        1.0 / (std::f64::consts::LN_10 * (grains + 1.0).sqrt())
    }

    /// The log-exposure fluctuation for one layer of one pixel.
    #[must_use]
    pub fn jitter(&self, x: usize, y: usize, mean_density: f64, channel: usize) -> f64 {
        self.sigma(mean_density, channel) * self.normal(x, y, channel)
    }

    /// A standard normal, deterministic in the pixel, the layer and the seed.
    fn normal(&self, x: usize, y: usize, channel: usize) -> f64 {
        let u1 = self.uniform(x, y, channel, 0);
        let u2 = self.uniform(x, y, channel, 1);
        (-2.0 * u1.ln()).sqrt() * (std::f64::consts::TAU * u2).cos()
    }

    /// Bits of the state a draw keeps.
    ///
    /// Twenty-three, not the fifty-three a f64 draw would use: a shader has no
    /// f64, so a value built from more bits than an f32 can hold is a different
    /// number there, and the two backends would produce two different films.
    /// Twenty-three bits are exact in both — `(bits + 0.5) * 2^-23` is
    /// representable to the last bit either way — so both draw the same one.
    ///
    /// The cost is a coarser draw: `u1` no longer reaches below `2^-24`, so the
    /// normal caps at about five sigma. Grain is not a tail measurement, and the
    /// distribution of the visible fluctuation is set by the counting statistics,
    /// not by the resolution of the generator.
    const UNIFORM_BITS: u64 = 23;

    /// A uniform in `(0, 1)`: the Box–Muller transform cannot take zero.
    fn uniform(&self, x: usize, y: usize, channel: usize, lane: u64) -> f64 {
        let mut state = self.seed.wrapping_mul(0xD6E8_FEB8_6659_FD93)
            ^ (x as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15)
            ^ (y as u64).wrapping_mul(0xC2B2_AE3D_27D4_EB4F)
            ^ (channel as u64).wrapping_mul(0x1656_67B1_9E37_79F9)
            ^ lane.wrapping_mul(0x2545_F491_4F6C_DD1D);
        let bits = splitmix64(&mut state) >> (64 - Self::UNIFORM_BITS);
        (bits as f64 + 0.5) * (1.0 / (1u64 << Self::UNIFORM_BITS) as f64)
    }
}

/// SplitMix64: small, fast, and good enough for a grain field.
///
/// The generator is re-seeded from the coordinates for every sample rather than
/// advanced along the image, so the grain does not depend on how the image was
/// split into rows or tiles.
///
/// It is 64-bit arithmetic, and WGSL has no 64-bit integers, so the shader that
/// reproduces this runs it on pairs of `u32`. That is a transcription of the
/// same algorithm rather than a different one — the alternative, a second
/// generator chosen for being portable, would produce a second film's grain.
fn splitmix64(state: &mut u64) -> u64 {
    *state = state.wrapping_add(0x9E37_79B9_7F4A_7C15);
    let mut z = *state;
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn field(pixel_area: f64) -> GrainField {
        GrainField {
            width: 4,
            height: 4,
            pixel_area_um2: pixel_area,
            grains_per_um2: [GrainField::DEFAULT_GRAINS_PER_UM2; 3],
            seed: 7,
        }
    }

    /// Selwyn's law: the standard deviation is set by the aperture area, so half
    /// the area is √2 times the graininess.
    #[test]
    fn sigma_follows_the_aperture_area() {
        let big = field(2300.0); // a 48 µm square, the aperture granularity is quoted at
        let half = field(1150.0);
        let ratio = half.sigma(1.0, 0) / big.sigma(1.0, 0);
        assert!((ratio - 2.0_f64.sqrt()).abs() < 0.02, "ratio {ratio}");
    }

    /// Counting statistics, stated plainly: the fewer grains that have developed,
    /// the larger the *relative* fluctuation in the exposure. The visible grain
    /// is this number multiplied by the curve's slope, which is why a blank frame
    /// and a shoulder both look clean — see the end-to-end test in `pipeline`.
    #[test]
    fn sigma_is_largest_where_fewest_grains_have_developed() {
        let field = field(36.0);
        assert!(field.sigma(0.0, 0) > field.sigma(1.0, 0));
        assert!(field.sigma(1.0, 0) > field.sigma(3.0, 0));
    }

    /// The number that matters: at a 48 µm aperture and D = 1 this should land
    /// near the published 0.005, or the placeholder density is wrong.
    #[test]
    fn the_placeholder_density_reproduces_a_published_granularity() {
        let field = field(2300.0);
        let sigma = field.sigma(1.0, 0);
        assert!(
            (0.004..0.007).contains(&sigma),
            "sigma {sigma} at a 48 µm aperture"
        );
    }

    #[test]
    fn the_same_seed_draws_the_same_grain() {
        let a = field(36.0);
        let b = field(36.0);
        assert_eq!(a.jitter(2, 3, 1.0, 0), b.jitter(2, 3, 1.0, 0));
        assert_ne!(a.jitter(2, 3, 1.0, 0), a.jitter(2, 3, 1.0, 1));
        assert_ne!(a.jitter(2, 3, 1.0, 0), a.jitter(3, 3, 1.0, 0));
    }

    /// The fluctuation has to be zero-mean, or it would shift the exposure rather
    /// than roughen it.
    #[test]
    fn the_fluctuation_has_no_bias() {
        let field = field(36.0);
        let n = 20_000;
        let mut sum = 0.0;
        for index in 0..n {
            sum += field.normal(index % 500, index / 500, 0);
        }
        let mean = sum / n as f64;
        assert!(mean.abs() < 0.03, "mean {mean}");
    }
}
