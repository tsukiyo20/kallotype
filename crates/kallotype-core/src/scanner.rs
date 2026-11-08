//! The scan: the optics and the noise between the print and the file.
//!
//! The model ends with a scan — dye unmixing, a neutral axis, an observer — and
//! that scan has no space in it. Everything it reads is a single number per
//! pixel, so the last stage of the chain is the one stage that could not be
//! wrong about texture: it had none.
//!
//! A negative scan says what belongs there. `lasvegas.dng` (Fuji NPH400,
//! 3.555 µm per pixel) was measured over its flat patches, and the finding was
//! uncomfortable: the film's own silver is not what a consumer scan shows. The
//! scan carries a density texture of 0.60 % through a 48 µm aperture, correlated
//! over 3.2 µm — half again the film's published granularity at its own peak,
//! measured where the developed silver contributes a fraction of it.
//!
//! Two things say it is not grain. Its amplitude is flat across the densities
//! the scan has (0.0060 to 0.0067 from D = 0.04 to 0.29, where the curve's slope
//! is rising steeply and a film's granularity cannot be flat), and the three
//! channels come out with the same correlation length *and* a common field —
//! `ρ = 0.69` between red and green, 0.83 between green and blue. Three
//! emulsions do not share a grain field. What does is something every sample
//! sees at once: the illumination, the optics, or the base's own texture. Which
//! of those it is cannot be told from one scan, and the model does not claim
//! to know.
//!
//! So the stage models the texture that was measured and nothing else:
//!
//! - a density texture, achromatic in part, with the measured length and
//!   amplitude. `shared` is the fraction of its variance the channels have in
//!   common, which is the cross-channel correlation the scan showed;
//! - an optics blur on the print, in micrometres. **Unmeasured**: the
//!   measurement above cannot separate the optics from the texture that rides
//!   on it, so the default is no blur rather than a number that would pretend
//!   to be a point-spread function.
//!
//! Whether the texture is fixed in the scanner (a dust-and-condenser pattern
//! that would repeat from scan to scan) or redrawn every frame is also not
//! known, and it matters for the two-scan test that would separate the scan
//! from the film: a fixed pattern is *not* independent between scans. This
//! model draws it fresh, and says so here rather than in a footnote.

use crate::psf::{convolve, gaussian_blur, gaussian_kernel};

/// The aperture granularity is quoted through, in micrometres.
pub const APERTURE_UM: f64 = 48.0;

/// A scan: what the optics and the sensor add to the print.
#[derive(Debug, Clone, Copy)]
pub struct Scanner {
    /// Correlation length of the density texture, in micrometres.
    pub texture_um: f64,
    /// Its rms through a [`APERTURE_UM`] aperture, in density.
    pub texture_density: f64,
    /// Fraction of the texture's variance the three channels share, `0..=1`.
    pub shared: f64,
    /// Gaussian optics on the print, in micrometres. Zero is no blur.
    pub optics_um: f64,
    /// Seed: the texture is a fixture, not a different scan every render.
    pub seed: u64,
}

impl Scanner {
    /// The numbers measured from `lasvegas.dng`.
    ///
    /// The one thing a single scan cannot do is split what it measures into the
    /// parts that made it, so this is the whole texture as one number per
    /// property. It is a scan's, not a film's: a stock must not carry it.
    #[must_use]
    pub fn measured() -> Self {
        Self {
            texture_um: 3.25,
            texture_density: 0.0060,
            shared: 0.70,
            optics_um: 0.0,
            seed: 0,
        }
    }

    /// Whether the scan would change a pixel at all.
    #[must_use]
    pub fn is_idle(&self) -> bool {
        self.optics_um <= 0.0 && (self.texture_density <= 0.0 || self.texture_um <= 0.0)
    }

    /// Scan a finished print in place.
    ///
    /// `pixels` are linear reflectance, one per channel. The optics blur that
    /// (light is convolved, not density), then the sensor's texture multiplies
    /// it back down in density, `R·10^-n`, which is how a density fluctuation
    /// appears in a linear measurement.
    pub fn apply(&self, pixels: &mut [[f64; 3]], width: usize, height: usize, pixel_um: f64) {
        if width == 0 || height == 0 || pixel_um <= 0.0 {
            return;
        }
        if self.optics_um > 0.0 {
            let sigma_px = self.optics_um / pixel_um;
            let mut planes = vec![vec![0.0; width * height]; 3];
            for (index, pixel) in pixels.iter().enumerate() {
                for (plane, value) in planes.iter_mut().zip(pixel) {
                    plane[index] = *value;
                }
            }
            let blurred: Vec<Vec<f64>> = planes
                .iter()
                .map(|plane| gaussian_blur(plane, width, height, sigma_px))
                .collect();
            for (index, pixel) in pixels.iter_mut().enumerate() {
                for (value, plane) in pixel.iter_mut().zip(&blurred) {
                    *value = plane[index];
                }
            }
        }
        if self.texture_density <= 0.0 || self.texture_um <= 0.0 {
            return;
        }

        // The texture's shape: a Gaussian of `sigma_px`, normalised to unit L2
        // so the field keeps the variance it is given, and its `P` — the
        // autocorrelation summed along one axis, the number of pixels one
        // feature stands behind. `P²` is what a 48 µm aperture would otherwise
        // over-count, exactly as the grain's stencil is corrected.
        let sigma_px = self.texture_um / (std::f64::consts::SQRT_2 * pixel_um);
        let kernel = l2_normalised(sigma_px);
        let radius = kernel.len() / 2;
        let mut per_axis = 0.0;
        for lag in 0..=radius {
            let mut pair = 0.0;
            for tap in 0..(kernel.len() - lag) {
                pair += kernel[tap] * kernel[tap + lag];
            }
            per_axis += if lag == 0 { pair } else { 2.0 * pair };
        }
        // Per-pixel sigma that puts `texture_density` through a 48 µm aperture.
        let sigma =
            self.texture_density * APERTURE_UM / (pixel_um * per_axis.max(f64::MIN_POSITIVE));
        let shared = self.shared.clamp(0.0, 1.0);
        let spread = (1.0 - shared).sqrt();
        let common_scale = shared.sqrt() * sigma;
        let own_scale = spread * sigma;

        // One white plane per field, filtered once: hashing the noise inside the
        // stencil would compute the same numbers `k²` times, and a twelve
        // megapixel frame then takes a minute instead of a second.
        let common = convolve(&self.white(width, height, 0), width, height, &kernel);
        let mut own = Vec::with_capacity(3);
        for channel in 0..3 {
            own.push(convolve(
                &self.white(width, height, 1 + channel),
                width,
                height,
                &kernel,
            ));
        }
        for (index, pixel) in pixels.iter_mut().enumerate() {
            for (channel, value) in pixel.iter_mut().enumerate() {
                let density = common_scale * common[index] + own_scale * own[channel][index];
                *value *= 10.0_f64.powf(-density);
            }
        }
    }

    /// A white field of unit variance, one per texture lane.
    fn white(&self, width: usize, height: usize, lane: usize) -> Vec<f64> {
        let mut plane = Vec::with_capacity(width * height);
        for y in 0..height {
            for x in 0..width {
                plane.push(self.unit_normal(x, y, lane));
            }
        }
        plane
    }

    /// A standard normal, deterministic in the pixel, the layer and the seed.
    ///
    /// The same generator the grain uses — SplitMix64 and Box–Muller — because
    /// two generators in one image is one too many, and because a draw shared
    /// with the grain is a draw that can be checked against it.
    fn unit_normal(&self, x: usize, y: usize, lane: usize) -> f64 {
        let u1 = self.uniform(x, y, lane, 0);
        let u2 = self.uniform(x, y, lane, 1);
        (-2.0 * u1.ln()).sqrt() * (std::f64::consts::TAU * u2).cos()
    }

    /// A uniform in `(0, 1)`, twenty-three bits like the grain's.
    fn uniform(&self, x: usize, y: usize, lane: usize, draw: usize) -> f64 {
        let mut state = self.seed.wrapping_mul(0xD6E8_FEB8_6659_FD93)
            ^ (x as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15)
            ^ (y as u64).wrapping_mul(0xC2B2_AE3D_27D4_EB4F)
            ^ (lane as u64).wrapping_mul(0x1656_67B1_9E37_79F9)
            ^ (draw as u64).wrapping_mul(0x2545_F491_4F6C_DD1D);
        let bits = splitmix64(&mut state) >> 41;
        (bits as f64 + 0.5) * (1.0 / 8_388_608.0)
    }
}

/// A Gaussian kernel normalised to unit L2 norm, so filtering keeps variance.
fn l2_normalised(sigma_px: f64) -> Vec<f64> {
    let mut kernel = gaussian_kernel(sigma_px.max(1e-3));
    let norm = kernel
        .iter()
        .map(|weight| weight * weight)
        .sum::<f64>()
        .sqrt();
    if norm > 0.0 {
        for weight in &mut kernel {
            *weight /= norm;
        }
    }
    kernel
}

/// SplitMix64, the generator the grain already uses.
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

    /// A 48 µm aperture must read the measured granularity, and one pixel must
    /// read more: the same fluctuation, spread over the texture's length.
    #[test]
    fn a_flat_print_scans_at_the_measured_granularity() {
        // 4.8 µm per pixel makes a 48 µm aperture ten pixels square.
        let scanner = Scanner::measured();
        let mut pixels = vec![[0.5; 3]; 400 * 400];
        scanner.apply(&mut pixels, 400, 400, 4.8);
        let mut means = Vec::new();
        for y in (10..390).step_by(10) {
            for x in (10..390).step_by(10) {
                let mut sum = 0.0;
                for dy in 0..10 {
                    for dx in 0..10 {
                        let value = pixels[(y + dy) * 400 + x + dx][1];
                        sum += -value.log10();
                    }
                }
                means.push(sum / 100.0);
            }
        }
        let mean = means.iter().sum::<f64>() / means.len() as f64;
        let aperture =
            (means.iter().map(|m| (m - mean).powi(2)).sum::<f64>() / means.len() as f64).sqrt();
        assert!(
            (aperture - scanner.texture_density).abs() < 0.0015,
            "48 µm granularity {aperture:.4}, expected {:.4}",
            scanner.texture_density
        );

        let per_pixel = {
            let values: Vec<f64> = pixels
                .iter()
                .skip(10 * 400)
                .take(380 * 400)
                .map(|p| -p[1].log10())
                .collect();
            let mean = values.iter().sum::<f64>() / values.len() as f64;
            (values.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / values.len() as f64).sqrt()
        };
        assert!(
            per_pixel > 2.0 * aperture,
            "the texture is too smooth: {per_pixel:.4} per pixel against {aperture:.4} at 48 µm"
        );
    }

    /// The measured cross-channel correlation is what `shared` means: the
    /// texture is one field seen three times, not three independent ones.
    /// Drawing it per channel would make a scan of a flat print look like a
    /// colour film's grain, which is exactly what the negative was measured
    /// *not* to be.
    #[test]
    fn the_texture_is_shared_by_the_channels() {
        let scanner = Scanner::measured();
        let mut pixels = vec![[0.5; 3]; 256 * 256];
        scanner.apply(&mut pixels, 256, 256, 4.8);
        let density: Vec<[f64; 3]> = pixels
            .iter()
            .map(|p| [0usize, 1, 2].map(|c| -p[c].log10()))
            .collect();
        let mean = [
            density.iter().map(|d| d[0]).sum::<f64>() / density.len() as f64,
            density.iter().map(|d| d[1]).sum::<f64>() / density.len() as f64,
            density.iter().map(|d| d[2]).sum::<f64>() / density.len() as f64,
        ];
        let mut worst = 0.0_f64;
        for (a, b) in [(0usize, 1usize), (0, 2), (1, 2)] {
            let mut cov = 0.0;
            let mut va = 0.0;
            let mut vb = 0.0;
            for d in &density {
                let da = d[a] - mean[a];
                let db = d[b] - mean[b];
                cov += da * db;
                va += da * da;
                vb += db * db;
            }
            let rho = cov / (va * vb).sqrt();
            worst = worst.max((rho - scanner.shared).abs());
        }
        assert!(
            worst < 0.1,
            "cross-channel correlation missed `shared` by {worst:.2}"
        );
    }

    /// The optics convolve light, so a step edge becomes a ramp; with no optics
    /// the print goes through unchanged.
    #[test]
    fn the_optics_blur_the_print_and_nothing_else() {
        let idle = Scanner {
            texture_density: 0.0,
            optics_um: 0.0,
            ..Scanner::measured()
        };
        assert!(idle.is_idle());
        let mut pixels = vec![[0.2; 3]; 32 * 8];
        for pixel in pixels.iter_mut().skip(16) {
            *pixel = [0.8; 3];
        }
        let original = pixels.clone();
        idle.apply(&mut pixels, 32, 8, 4.8);
        assert_eq!(pixels, original, "an idle scan changed the print");

        let mut blurred = original.clone();
        Scanner {
            optics_um: 4.8,
            ..idle
        }
        .apply(&mut blurred, 32, 8, 4.8);
        let ramp = blurred[4 * 32 + 12][0];
        assert!(ramp > 0.2 && ramp < 0.8, "no ramp: {ramp}");
        assert!(
            (blurred[4 * 32 + 24][0] - 0.8).abs() < 0.05,
            "the flat kept its value"
        );
    }

    #[test]
    fn the_same_seed_scans_the_same_frame() {
        let scanner = Scanner::measured();
        let mut a = vec![[0.4; 3]; 64 * 64];
        let mut b = a.clone();
        scanner.apply(&mut a, 64, 64, 3.555);
        scanner.apply(&mut b, 64, 64, 3.555);
        assert_eq!(a, b);
        let mut other = vec![[0.4; 3]; 64 * 64];
        Scanner { seed: 7, ..scanner }.apply(&mut other, 64, 64, 3.555);
        assert_ne!(a, other);
    }
}
