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
//! ## Where `n` comes from
//!
//! `n` is not a free parameter. The manufacturer publishes rms granularity
//! against density, measured through a 48 µm aperture; that is `sigma_D`, and
//! with the curve's local slope `gamma`,
//!
//! ```text
//! sigma_D = gamma · sigma_logE
//! ```
//!
//! so the chart pins `n` for every layer of the stock it belongs to. For
//! `vision3_500t` the three layers come out at 0.62, 0.51 and 0.07 grains per
//! µm² — the blue record needs nine times fewer than the red to be nine times
//! grainier, which is what being the front layer of a fast film means.
//!
//! "Grains" is a deliberate simplification of "effective scattering centres". A
//! developed image's noise is dominated by clumping, so `n` is far below a count
//! of silver halide crystals — a few tenths per µm² rather than a few per µm².
//! It is whatever reproduces the published curve, and `emulsion` holds it per
//! stock.
//!
//! Development is not linked in yet. Grain clumping does grow with development —
//! the literature is clear about the direction and says little about the law —
//! but a made-up exponent is worse than an honest gap, so the relation waits for
//! a measurement.
//!
//! The one scan in the tree was measured for it and cannot answer. Its flat
//! areas are all in the toe, where the film has developed almost nothing and
//! the scanner's own noise is what varies; all three channels come out at the
//! same correlation length, which three emulsions would not. That number is the
//! scanner's, and it stays in the measurement note rather than being promoted
//! into a stock: see `docs/measurements/2026-11-08-grain-vs-density.md`.

use crate::emulsion::FilmStock;

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
    /// Whether the three channels share one grain field.
    ///
    /// A colour film has three separate emulsions, so three independent draws
    /// is the physical statement. A silver film has one record: its grain is
    /// one field, and drawing it three times gives a monochrome negative a
    /// colour cast made of noise.
    pub monochrome: bool,
    /// Correlation length of the grain in micrometres, one per layer.
    ///
    /// This is the *spatial* scale the counting statistics do not carry: a
    /// grain covers area, so neighbouring pixels agree over roughly this
    /// distance, and the published granularity — a variance through a 48 µm
    /// aperture — averages that correlation away.
    ///
    /// It is a correlation length, not a diameter: it is the width of the
    /// autocovariance of a flat scan's granularity, which is what
    /// `scripts/grain_spectrum.py` measures. Until a stock's own is measured,
    /// the mean grain spacing `1/√n` stands in — the distance at which the
    /// measured density tiles the area, and a lower bound on the real one.
    ///
    /// Measure it on a *mid-density* flat, not on the thin sky of a night
    /// frame. There the film has developed almost nothing, and what a scan
    /// shows is the scanner: the same 3.2 µm in all three channels is the
    /// giveaway, because three emulsions do not share a grain size. The
    /// number is then a property of the scanner's optics, not of the film —
    /// see `docs/measurements/2026-11-08-grain-vs-density.md`.
    pub grain_um: [f64; 3],
    /// Radius of the correlation stencil, in pixels, one per layer. Zero when
    /// the grain is smaller than a tenth of a pixel, where the kernel is a
    /// delta and drawing it would only cost time.
    pub radius: [usize; 3],
    /// Separable weights for the stencil, centre at [`Self::CENTRE`].
    ///
    /// Symmetric by construction — tap `CENTRE ± k` are the same number — and
    /// already scaled by the aperture correction, so the field they draw is
    /// the one [`Self::sigma`] describes *through an aperture*, not per pixel.
    pub weights: [[f64; Self::STENCIL]; 3],
}

impl GrainField {
    /// Width of the separable stencil: five taps, so a radius of two.
    const STENCIL: usize = 5;
    /// How much narrower a five-tap stencil is than the Gaussian it samples.
    ///
    /// A continuous Gaussian of `sigma` has an autocovariance of
    /// `exp(-r²/4sigma²)`. Its five-tap version is aliased enough that the
    /// rendered field's correlation length comes out 0.74 of the continuous
    /// prediction — measured by rendering a flat patch at a known pitch and
    /// running `scripts/grain_spectrum.py` over it. This is a property of the
    /// discretisation, not of the film, so it lives here and not in the data.
    const STENCIL_NARROWING: f64 = 0.74;
    /// Index of the centre tap.
    pub const CENTRE: usize = 2;

    /// Grain density for a stock that has not been measured, in grains per µm².
    ///
    /// A placeholder, at the order of magnitude a physical grain count would
    /// give. The measured stocks carry their own, derived from the published
    /// granularity curve, and it is nine times smaller for the blue layer.
    pub const DEFAULT_GRAINS_PER_UM2: f64 = 3.6;

    /// A field for an image `width × height` pixels covering `frame_mm` across,
    /// with the fallback grain density.
    ///
    /// Use [`Self::for_stock`] when the film is known: the measured stocks carry
    /// their own, and they differ by a factor of nine between layers.
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
            monochrome: false,
            grain_um: [0.0; 3],
            radius: [0; 3],
            weights: [[0.0; Self::STENCIL]; 3],
        }
        .with_grain_sizes(Self::spacing_of(&[Self::DEFAULT_GRAINS_PER_UM2; 3]))
    }

    /// A field whose grain density is the stock's own.
    #[must_use]
    pub fn for_stock(
        width: usize,
        height: usize,
        frame_mm: f64,
        seed: u64,
        stock: &FilmStock,
    ) -> Self {
        Self {
            grains_per_um2: stock.grains_per_um2,
            monochrome: stock.process == crate::emulsion::FilmProcess::Monochrome,
            ..Self::new(width, height, frame_mm, seed)
        }
        .with_grain_sizes(Self::spacing_of(&stock.grains_per_um2))
    }

    /// Mean grain spacing, `1/√n`, in micrometres, one per layer.
    ///
    /// The area one developed grain occupies at the measured density. It is
    /// what a density of `n` grains per µm² tiles into, and it is the stand-in
    /// for a grain size until a stock's own has been measured from a scan.
    #[must_use]
    pub fn spacing_of(grains_per_um2: &[f64; 3]) -> [f64; 3] {
        std::array::from_fn(|layer| {
            let n = grains_per_um2[layer];
            if n > 0.0 { 1.0 / n.sqrt() } else { 0.0 }
        })
    }

    /// Set the grain diameter per layer, and build the stencil it implies.
    ///
    /// The kernel is a Gaussian of `sigma = L/(√2)` where `L` is the
    /// correlation length: a field filtered by a Gaussian of `sigma` has an
    /// autocovariance of `exp(-r²/4sigma²)`, whose own width is `√2·sigma`, so
    /// dividing by √2 makes the rendered grain's correlation length the number
    /// that was measured. A grain narrower than a tenth of a pixel leaves the
    /// stencil at radius zero — there the kernel is a delta and the per-pixel
    /// draw is already the answer.
    ///
    /// The taps are normalised to unit L2 norm — which keeps the *shape* of
    /// the grain independent of the counting statistics — and then multiplied
    /// by `P^-1/2`, where `P = Σ_d γ(d)` is the autocorrelation summed along
    /// one axis and `P²` is the number of pixels one clump stands behind. That
    /// second step is the aperture recalibration, and it is not optional.
    ///
    /// `n` was derived from an rms quoted through a 48 µm aperture, so `sigma`
    /// is the fluctuation a *wide* aperture sees. A correlated field with `P²`
    /// pixels per clump and the same per-pixel variance would put `P²` times
    /// that variance behind a wide aperture — the data sheet would say one
    /// thing and the print would show another, growing grainier as the clump
    /// got bigger, which is not a film model but a volume knob. Scaling the
    /// taps by `P^-1/2` collapses the two statements back into one: a wide
    /// aperture sees exactly the counting statistics, and one pixel sees `1/P`
    /// of them. That is the physical picture — the same fluctuation, spread
    /// over a clump instead of shouted by one pixel — and it is why a 3.5 µm
    /// clump at 4.8 µm per pixel draws pixels at 43 % of the counting noise
    /// while the granularity a densitometer reads does not move.
    ///
    /// `P` is computed from the taps that are actually drawn, so a stencil
    /// truncated by `Self::STENCIL` is corrected for what it is, not for the
    /// Gaussian it was meant to be.
    #[must_use]
    pub fn with_grain_sizes(mut self, grain_um: [f64; 3]) -> Self {
        self.grain_um = grain_um;
        let pixel_um = self.pixel_area_um2.sqrt().max(1e-9);
        for (layer, &diameter) in grain_um.iter().enumerate() {
            let sigma_px =
                diameter.max(0.0) / (std::f64::consts::SQRT_2 * Self::STENCIL_NARROWING) / pixel_um;
            let radius = if sigma_px < 0.1 {
                0
            } else {
                (3.0 * sigma_px).ceil().min((Self::STENCIL / 2) as f64) as usize
            };
            self.radius[layer] = radius;
            let mut weights = [0.0; Self::STENCIL];
            if radius == 0 {
                weights[Self::CENTRE] = 1.0;
            } else {
                for (tap, weight) in weights.iter_mut().enumerate() {
                    let offset = tap as f64 - Self::CENTRE as f64;
                    if offset.abs() <= radius as f64 {
                        *weight = (-0.5 * (offset / sigma_px).powi(2)).exp();
                    }
                }
                let norm: f64 = weights.iter().map(|weight| weight * weight).sum::<f64>();
                let norm = norm.sqrt();
                for weight in &mut weights {
                    *weight /= norm;
                }
                // Pixels per clump: the autocorrelation summed over the taps
                // that survived, one factor per axis.
                let mut per_axis = 0.0;
                for lag in 0..=radius {
                    let mut pair = 0.0;
                    for tap in 0..(Self::STENCIL - lag) {
                        pair += weights[tap] * weights[tap + lag];
                    }
                    per_axis += if lag == 0 { pair } else { 2.0 * pair };
                }
                // `P²` is the number of pixels the clump stands behind. A
                // separable kernel scaled by `a` scales the 2-D variance by
                // `a⁴`, so `a = P^-1/2` puts `1/P²` of it in each pixel — the
                // aperture correction — and leaves the per-pixel sigma at `1/P`
                // of the counting statistics.
                let amplitude = 1.0 / per_axis.sqrt();
                for weight in &mut weights {
                    *weight *= amplitude;
                }
            }
            self.weights[layer] = weights;
        }
        self
    }

    /// Whether the grain is correlated across pixels.
    ///
    /// When it is, the drawing backend has to convolve, and this one knows how.
    #[must_use]
    pub fn has_kernel(&self) -> bool {
        self.radius.iter().any(|&radius| radius > 0)
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
        // A silver film is one record: one draw *and* one size. Taking the
        // amplitude from the layer would give the three channels three gains
        // and put the colour back as brightness instead of as pattern.
        let record = if self.monochrome { 0 } else { channel };
        self.sigma(mean_density, record) * self.correlated(x, y, record)
    }

    /// One layer's grain at a pixel, with the grain's own spatial size.
    ///
    /// A grain is not a point: it covers area, so the fluctuation at one pixel
    /// is shared with its neighbours. The counting statistics cannot say that
    /// — they give the variance through an aperture — so the correlation is
    /// imposed here, by filtering the field with the stencil the grain's
    /// diameter implies. The taps carry the aperture correction described on
    /// [`Self::with_grain_sizes`], so this is the one place the shared variance
    /// is spread back over the pixels it belongs to. Coordinates outside the
    /// image repeat the edge, which keeps the draw a pure function of the pixel
    /// and identical on any backend that implements the same stencil.
    fn correlated(&self, x: usize, y: usize, channel: usize) -> f64 {
        let radius = self.radius[channel];
        if radius == 0 {
            return self.normal(x, y, channel);
        }
        let weights = &self.weights[channel];
        let reach = radius as isize;
        let mut sum = 0.0;
        for dy in -reach..=reach {
            let row = clamp(y, dy, self.height);
            let wy = weights[(dy + Self::CENTRE as isize) as usize];
            for dx in -reach..=reach {
                let column = clamp(x, dx, self.width);
                sum += wy
                    * weights[(dx + Self::CENTRE as isize) as usize]
                    * self.normal(column, row, channel);
            }
        }
        sum
    }

    /// A standard normal, deterministic in the pixel, the layer and the seed.
    fn normal(&self, x: usize, y: usize, channel: usize) -> f64 {
        // One record, one field: every layer draws the same numbers.
        let channel = if self.monochrome { 0 } else { channel };
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

/// A coordinate shifted by an offset, held inside the image.
fn clamp(value: usize, offset: isize, limit: usize) -> usize {
    let shifted = value as isize + offset;
    shifted.clamp(0, limit.saturating_sub(1) as isize) as usize
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

    /// The stencil has to keep the variance the counting statistics set: it
    /// changes the grain's shape, not its size. And a grain wider than a pixel
    /// has to make neighbouring pixels agree, which is the whole point.
    #[test]
    fn a_wide_grain_correlates_its_neighbours() {
        // 36 mm across 7040 pixels is 5.11 µm per pixel; a 10 µm grain is
        // nearly two pixels across.
        let field = GrainField::new(7040, 100, 36.0, 3).with_grain_sizes([10.0; 3]);
        assert!(
            field.has_kernel(),
            "a 10 µm grain must be wider than a pixel"
        );

        let (mut sum_lag, mut sum_sq, mut count) = (0.0, 0.0, 0.0);
        for y in 10..90 {
            for x in 10..4000 {
                let here = field.jitter(x, y, 1.0, 0);
                let right = field.jitter(x + 1, y, 1.0, 0);
                sum_lag += here * right;
                sum_sq += here * here;
                count += 1.0;
            }
        }
        let lag_one = (sum_lag / count) / (sum_sq / count);
        assert!(
            lag_one > 0.2,
            "neighbouring pixels should agree, lag-1 correlation {lag_one}"
        );

        // And below a tenth of a pixel of stencil width the kernel is a delta:
        // nothing is correlated and nothing is slower.
        let narrow = GrainField::new(7040, 100, 36.0, 3).with_grain_sizes([0.3; 3]);
        assert!(
            !narrow.has_kernel(),
            "a third of a micrometre is a delta here"
        );
    }

    /// The stencil carries the aperture correction. Through a 48 µm aperture a
    /// wide grain has to show the counting statistics — the published
    /// granularity — and not `√S` times them. Getting this wrong is invisible
    /// in a crop and obvious in a print: the film gets grainier as its clump
    /// grows, which is a volume knob, not a model.
    #[test]
    fn a_wide_aperture_sees_the_counting_statistics_with_or_without_a_stencil() {
        // 4.8 µm per pixel makes a 48 µm aperture exactly ten pixels square.
        let frame_mm = 400.0 * 4.8 / 1000.0;
        let flat = GrainField::new(400, 400, frame_mm, 11).with_grain_sizes([0.02; 3]);
        let clumped = GrainField::new(400, 400, frame_mm, 11).with_grain_sizes([3.5; 3]);
        assert!(clumped.has_kernel(), "3.5 µm is wider than a pixel here");

        // A 48 µm aperture sees one tenth of the per-pixel fluctuation.
        let expected = clumped.sigma(1.0, 0) * 4.8 / 48.0;
        for field in [&flat, &clumped] {
            let measured = aperture_rms(field, 10);
            assert!(
                (measured / expected - 1.0).abs() < 0.1,
                "48 µm granularity {measured:.4e}, expected {expected:.4e}"
            );
        }

        // And one pixel of the clumped field is quieter than the counting
        // statistics by exactly the share the stencil spends: the same
        // fluctuation, spread over the clump.
        let share: f64 = clumped.weights[0].iter().map(|w| w * w).sum();
        let per_pixel = aperture_rms(&clumped, 1) / clumped.sigma(1.0, 0);
        assert!(
            (share - per_pixel).abs() < 0.01,
            "the taps say {share:.3} per pixel, the field draws {per_pixel:.3}"
        );
    }

    /// The share a pixel keeps is the number the aperture table is made of:
    /// at 5.11 µm per pixel a 3.5 µm clump stands behind about five pixels, so
    /// one pixel keeps 0.445 of the counting statistics — and the 48 µm
    /// aperture keeps all of them.
    #[test]
    fn the_stencil_says_how_much_of_the_counting_statistics_one_pixel_keeps() {
        let field = GrainField::new(7040, 8, 36.0, 3).with_grain_sizes([3.5; 3]);
        let share: f64 = field.weights[0].iter().map(|w| w * w).sum();
        assert!(
            (share - 0.445).abs() < 0.01,
            "a 3.5 µm clump at 5.11 µm per pixel keeps {share:.3}, not 0.445"
        );
        // At half the pixel pitch the clump stands behind four times as many
        // pixels and each keeps less of it.
        let finer = GrainField::new(7040, 8, 12.0, 3).with_grain_sizes([3.5; 3]);
        let finer_share: f64 = finer.weights[0].iter().map(|w| w * w).sum();
        assert!(
            finer_share < share,
            "finer pixels keep less: {finer_share:.3} vs {share:.3}"
        );
    }

    /// Root mean square of the pixel average over `block × block` apertures.
    ///
    /// Interior blocks only: the field repeats its edge, and a block that leans
    /// on that duplication is not a sample of the grain.
    fn aperture_rms(field: &GrainField, block: usize) -> f64 {
        let mut sums = Vec::new();
        let mut y = block;
        while y + block < field.height {
            let mut x = block;
            while x + block < field.width {
                let mut sum = 0.0;
                for dy in 0..block {
                    for dx in 0..block {
                        sum += field.jitter(x + dx, y + dy, 1.0, 0);
                    }
                }
                sums.push(sum / (block * block) as f64);
                x += block;
            }
            y += block;
        }
        let mean = sums.iter().sum::<f64>() / sums.len() as f64;
        let variance = sums.iter().map(|s| (s - mean).powi(2)).sum::<f64>() / sums.len() as f64;
        variance.sqrt()
    }

    /// A silver film has one record, so its three layers must see one grain
    /// field. Drawing per layer gives a monochrome negative coloured noise —
    /// found by rendering one and looking at the channels.
    #[test]
    fn a_silver_film_draws_one_grain_field() {
        let mut field = GrainField::new(8, 8, 36.0, 7);
        field.monochrome = true;
        for y in 0..8 {
            for x in 0..8 {
                let red = field.jitter(x, y, 1.0, 0);
                assert_eq!(
                    red,
                    field.jitter(x, y, 1.0, 1),
                    "layer 1 differs at {x},{y}"
                );
                assert_eq!(
                    red,
                    field.jitter(x, y, 1.0, 2),
                    "layer 2 differs at {x},{y}"
                );
            }
        }

        field.monochrome = false;
        assert_ne!(
            field.jitter(3, 4, 1.0, 0),
            field.jitter(3, 4, 1.0, 1),
            "a colour film's layers are separate emulsions"
        );
    }

    fn field(pixel_area: f64) -> GrainField {
        GrainField {
            monochrome: false,
            width: 4,
            height: 4,
            pixel_area_um2: pixel_area,
            grains_per_um2: [GrainField::DEFAULT_GRAINS_PER_UM2; 3],
            seed: 7,
            grain_um: [0.0; 3],
            radius: [0; 3],
            weights: [[0.0; GrainField::STENCIL]; 3],
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

    /// The placeholder is the fallback, so it should sit where a physical grain
    /// count would: a few thousand grains under a 48 µm aperture, and a
    /// log-exposure fluctuation of a few thousandths.
    #[test]
    fn the_fallback_density_is_the_order_of_a_real_grain_count() {
        let field = field(2300.0);
        let sigma = field.sigma(1.0, 0);
        assert!(
            (0.002..0.008).contains(&sigma),
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
