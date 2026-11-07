//! The emulsion's own blur: how much a real negative softens an image.
//!
//! The model had no spatial response of its own until this file. It could
//! reproduce a film's tone, colour and grain, and its pixels were still as sharp
//! as the arithmetic that made them — where a real negative has already lost
//! half its contrast at 50 cycles/mm.
//!
//! ## The measurement
//!
//! The VISION3 500T data sheet (H-1-5219, page 3) draws the film's
//! modulation-transfer curve for the three layers, on logarithmic axes, from
//! 2.5 to about 90 cycles/mm. It is digitised in
//! `scripts/extract_mtf.py`, and a Gaussian fitted to it per layer gives
//!
//! | layer | sigma | response at 50 c/mm, fitted / measured |
//! |---|---|---|
//! | red | 3.12 µm | 0.61 / 0.58 |
//! | green | 3.57 µm | 0.52 / 0.50 |
//! | blue | 5.11 µm | 0.27 / 0.32 |
//!
//! with an rms of 0.04 over the whole curve. Blue is the softest, which is what
//! a shorter wavelength scattering in the emulsion should do.
//!
//! ## What the number is, and is not
//!
//! A **single Gaussian is an approximation**: the sheet's curve is flatter than
//! a Gaussian in the middle and heavier in the tail, and two Gaussians fit it
//! about a third better (0.03 against 0.04). One is used because the model has
//! one blur per channel, and 0.04 of MTF is below what a 4K scan of a film
//! resolves anyway.
//!
//! The sheet does not state the measuring aperture, so this sigma includes
//! whatever lens made the measurement. At f/5.6 that is a 0.9 µm Gaussian in
//! quadrature, which would take the red layer's 3.12 to 2.99 — a 4 % correction
//! that cannot be made without knowing the aperture, and is recorded here rather
//! than guessed at.
//!
//! The curve also **contains halation**, because halation is part of what blurs
//! a film. With `Finishing::halation` enabled as well, the halo's contribution
//! to the blur is counted twice; it is about a tenth of the total, which is the
//! size of the halation strengths themselves.

use crate::psf::gaussian_blur;

/// The film's spatial response, as a Gaussian per layer.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct EmulsionBlur {
    /// Standard deviation on the film, in micrometres, per layer (R, G, B).
    pub sigma_um: [f64; 3],
    /// Size of one pixel on the film, in micrometres across.
    pub pixel_um: f64,
}

impl EmulsionBlur {
    /// The measured VISION3 500T blur.
    #[must_use]
    pub fn measured(pixel_um: f64) -> Self {
        Self {
            sigma_um: [3.12, 3.57, 5.11],
            pixel_um,
        }
    }

    /// Whether the blur would change anything.
    #[must_use]
    pub fn is_noop(&self) -> bool {
        self.sigma_um.iter().all(|&sigma| sigma <= 0.0)
    }

    /// Blur the exposure, in place, layer by layer.
    ///
    /// This is applied in **linear exposure**, not in density: the blur happens
    /// to the light before development, which is why it runs before the grain.
    /// Blurring the developed density instead would turn highlights into grey
    /// rather than into soft highlights.
    pub fn apply(&self, log_e: &mut [[f64; 3]], width: usize, height: usize) {
        if self.is_noop() || width == 0 || height == 0 {
            return;
        }
        let pixels = (width * height).min(log_e.len());
        let height = pixels / width;
        if height == 0 {
            return;
        }
        for channel in 0..3 {
            let sigma_px = self.sigma_um[channel] / self.pixel_um.max(1e-9);
            if sigma_px <= 0.0 {
                continue;
            }
            let plane: Vec<f64> = log_e[..pixels]
                .iter()
                .map(|pixel| 10.0_f64.powf(pixel[channel]))
                .collect();
            let blurred = gaussian_blur(&plane, width, height, sigma_px);
            for (pixel, value) in log_e[..pixels].iter_mut().zip(blurred) {
                pixel[channel] = value.max(1e-10).log10();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const W: usize = 32;
    const H: usize = 32;

    /// A blur moves light; it does not make or lose it. The exposure plane has
    /// to come out with the same total, which a normalised kernel guarantees and
    /// a `sigma_px` mistake does not.
    #[test]
    fn the_blur_preserves_the_total_exposure() {
        // A background far enough down to contribute nothing: at -6 the 1023
        // unlit pixels would add 0.1 % on their own and the test would fail on
        // its own arithmetic rather than on the blur's.
        let mut buffer = vec![[-30.0; 3]; W * H];
        buffer[(H / 2) * W + W / 2] = [0.0; 3];
        let before = 10.0_f64.powf(0.0);
        EmulsionBlur::measured(2.0).apply(&mut buffer, W, H);
        let after: f64 = buffer.iter().map(|pixel| 10.0_f64.powf(pixel[0])).sum();
        // Relative, at the level f64 summation of a few hundred products reaches.
        assert!(
            (after - before).abs() < 1e-6 * before,
            "{after} against {before}"
        );
    }

    /// Blue scatters more than red, so a blue highlight has to spread wider.
    #[test]
    fn blue_spreads_further_than_red() {
        let mut buffer = vec![[-6.0; 3]; W * H];
        buffer[(H / 2) * W + W / 2] = [0.0; 3];
        EmulsionBlur::measured(2.0).apply(&mut buffer, W, H);
        let centre = (H / 2) * W + W / 2;
        let nearby = buffer[centre + 2];
        assert!(
            nearby[0] > nearby[2],
            "red {nearby:?} should be sharper than blue"
        );
    }

    /// A flat frame is the identity: this is a blur, and a uniform field has
    /// nothing to blur.
    #[test]
    fn a_flat_frame_is_unchanged() {
        let mut buffer = vec![[-1.0; 3]; W * H];
        EmulsionBlur::measured(2.0).apply(&mut buffer, W, H);
        for pixel in &buffer {
            assert!((pixel[0] + 1.0).abs() < 1e-9, "{pixel:?}");
        }
    }
}
