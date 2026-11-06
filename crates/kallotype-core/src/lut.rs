//! A baked lookup table for the spectral exposure.
//!
//! The hybrid reconstruction costs a non-negative least squares per pixel, which
//! is fine for a benchmark and hopeless for a 24 MP image. But the expensive part
//! produces only three numbers: the log exposure of each film layer. So the model
//! can be *distilled* into a three-dimensional table over RGB and interpolated
//! per pixel.
//!
//! The table is indexed on a **logarithmic** axis. Linear light spans several
//! decades between a shadow and a highlight, and a linear axis would spend most
//! of its resolution on values nobody photographs. Uniform steps in log10 give
//! uniform resolution in stops.

use crate::spectral::SpectralContext;

/// log10 of the smallest input the table covers.
pub const LOG_RANGE_MIN: f64 = -4.0;
/// log10 of the largest input the table covers.
pub const LOG_RANGE_MAX: f64 = 0.602_06; // log10(4.0)

/// A cubed lookup table mapping linear RGB to per-layer log exposure.
#[derive(Debug, Clone)]
pub struct ExposureLut {
    size: usize,
    /// `size^3` entries, index order `(r, g, b)`.
    data: Vec<[f32; 3]>,
}

impl ExposureLut {
    /// Bake a table by sampling `context` on a `size^3` grid.
    ///
    /// A size of 33 gives about 36 k samples: a few hundred milliseconds in
    /// release, half a megabyte on disk as `f32`.
    ///
    /// # Panics
    ///
    /// Panics if `size < 2`.
    #[must_use]
    pub fn bake(size: usize, context: &SpectralContext) -> Self {
        assert!(
            size >= 2,
            "a lookup table needs at least two samples per axis"
        );
        let mut data = Vec::with_capacity(size * size * size);
        for r in 0..size {
            let red = decode(r, size);
            for g in 0..size {
                let green = decode(g, size);
                for b in 0..size {
                    let blue = decode(b, size);
                    let log_e = context
                        .expose([red, green, blue])
                        .unwrap_or([LOG_RANGE_MIN; 3]);
                    data.push([log_e[0] as f32, log_e[1] as f32, log_e[2] as f32]);
                }
            }
        }
        Self { size, data }
    }

    /// Number of samples per axis.
    #[must_use]
    pub fn size(&self) -> usize {
        self.size
    }

    /// Bytes the table would occupy on disk as `f32`.
    #[must_use]
    pub fn byte_size(&self) -> usize {
        self.data.len() * 3 * std::mem::size_of::<f32>()
    }

    /// Trilinear interpolation, clamped at the edges.
    #[must_use]
    pub fn sample(&self, rgb: [f64; 3]) -> [f64; 3] {
        let positions = rgb.map(|value| encode(value) * (self.size - 1) as f64);
        let lower = positions.map(|p| (p.floor() as usize).min(self.size - 1));
        let upper = lower.map(|l| (l + 1).min(self.size - 1));
        let weights = std::array::from_fn::<f64, 3, _>(|axis| {
            let p = positions[axis];
            let base = lower[axis] as f64;
            (p - base).clamp(0.0, 1.0)
        });

        let mut out = [0.0_f64; 3];
        for corner in 0..8 {
            let pick = |axis: usize| {
                if (corner >> axis) & 1 == 1 {
                    upper[axis]
                } else {
                    lower[axis]
                }
            };
            let weight = (0..3).fold(1.0, |acc, axis| {
                acc * if (corner >> axis) & 1 == 1 {
                    weights[axis]
                } else {
                    1.0 - weights[axis]
                }
            });
            let index = (pick(0) * self.size + pick(1)) * self.size + pick(2);
            let entry = self.data[index];
            for channel in 0..3 {
                out[channel] += weight * f64::from(entry[channel]);
            }
        }
        out
    }
}

/// Map a linear value to the `[0, 1]` table coordinate.
fn encode(value: f64) -> f64 {
    let log = value.max(1e-10).log10();
    ((log - LOG_RANGE_MIN) / (LOG_RANGE_MAX - LOG_RANGE_MIN)).clamp(0.0, 1.0)
}

/// Inverse of [`encode`].
fn decode(index: usize, size: usize) -> f64 {
    let u = index as f64 / (size - 1) as f64;
    10.0_f64.powf(LOG_RANGE_MIN + u * (LOG_RANGE_MAX - LOG_RANGE_MIN))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encode_decode_round_trip() {
        for value in [0.0005, 0.01, 0.18, 1.0, 3.0] {
            let round_trip =
                10.0_f64.powf(LOG_RANGE_MIN + encode(value) * (LOG_RANGE_MAX - LOG_RANGE_MIN));
            assert!(
                (round_trip - value).abs() < 1e-3 * value.max(1.0),
                "{value} -> {round_trip}"
            );
        }
    }

    #[test]
    fn the_table_matches_the_model_it_was_baked_from() {
        let context = SpectralContext::new();
        let lut = ExposureLut::bake(33, &context);

        // The error is strongly skewed: the mean is tiny and the tail lives in
        // the extreme corners, where the polynomial reconstruction clamps at
        // zero and the mapping has a kink. Asserting a single maximum would
        // either fail on a corner or hide the distribution.
        let mut errors = Vec::new();
        for r in 0..10 {
            for g in 0..10 {
                for b in 0..10 {
                    let rgb = [
                        0.01 + 0.09 * f64::from(r),
                        0.01 + 0.09 * f64::from(g),
                        0.01 + 0.09 * f64::from(b),
                    ];
                    let direct = context.expose(rgb).unwrap();
                    let baked = lut.sample(rgb);
                    for channel in 0..3 {
                        errors.push((direct[channel] - baked[channel]).abs());
                    }
                }
            }
        }
        errors.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let count = errors.len();
        let mean = errors.iter().sum::<f64>() / count as f64;
        let p99 = errors[count * 99 / 100];

        assert!(mean < 0.005, "mean error {mean} decades");
        assert!(p99 < 0.05, "p99 error {p99} decades");
    }

    #[test]
    fn the_table_is_bounded_by_its_inputs() {
        let context = SpectralContext::new();
        let lut = ExposureLut::bake(9, &context);
        for rgb in [[0.0; 3], [1.0; 3], [10.0; 3]] {
            let out = lut.sample(rgb);
            for value in out {
                assert!(value.is_finite());
            }
        }
    }
}
