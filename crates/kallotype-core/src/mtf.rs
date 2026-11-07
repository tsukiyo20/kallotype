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
//! `scripts/extract_mtf.py`, and `scripts/fit_mtf_blur.py` fits one Gaussian per
//! layer over 5-60 cycles/mm and 20-100 % response:
//!
//! | layer | sigma | response at 50 c/mm, fitted / measured |
//! |---|---|---|
//! | red | 3.43 µm | 0.60 / 0.59 |
//! | green | 3.67 µm | 0.53 / 0.53 |
//! | blue | 4.64 µm | 0.32 / 0.33 |
//!
//! with an rms of 2.5 to 5.2 % of response. Blue is the softest, which is what
//! a shorter wavelength scattering in the emulsion should do.
//!
//! ## What the number is, and is not
//!
//! A **single Gaussian is an approximation**: the sheet's curve is flatter than
//! a Gaussian in the middle and heavier in the tail, so the residual is largest
//! where the curve is lowest. One is used because the model has one blur per
//! channel, and 5 % of response at 50 cycles/mm is below what a 4K scan of a
//! film resolves anyway.
//!
//! The window is a decision, and it is the same decision for every stock: across
//! the twelve layers now in the tree, 5-60 cycles/mm fits with a median rms of
//! 2.8 % against 4.5 % for 5-80. A wider window is not more honest, it is a
//! worse model of the same data.
//!
//! The sheet does not state the measuring aperture, so this sigma includes
//! whatever lens made the measurement. At f/5.6 that is a 0.9 µm Gaussian in
//! quadrature, which would take the red layer's 3.43 to 3.31 — a 3 % correction
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
            sigma_um: [3.43, 3.67, 4.64],
            pixel_um,
        }
    }

    /// The stock's own blur when its sheet published an MTF, and the compiled
    /// VISION3 fit when it did not — a borrow the stock's note declares.
    #[must_use]
    pub fn for_stock(film: &crate::emulsion::FilmStock, pixel_um: f64) -> Self {
        Self {
            sigma_um: film.sigma_um.unwrap_or([3.43, 3.67, 4.64]),
            pixel_um,
        }
    }

    /// Whether the blur would change anything **at this pixel size**.
    ///
    /// A film's blur is a few micrometres. A 35 mm frame rendered at 1200 pixels
    /// across is sampled every 30 µm, so the blur is a tenth of a pixel wide and
    /// doing it would be arithmetic that cannot show in the output. The same
    /// frame at 12000 pixels is sampled every 3 µm and the blur is most of a
    /// pixel — which is the resolution at which this term starts to matter, and
    /// the reason it is not simply always on.
    #[must_use]
    pub fn is_noop(&self) -> bool {
        let per_pixel = self.pixel_um.max(1e-9);
        self.sigma_um
            .iter()
            .all(|&sigma| sigma <= 0.0 || sigma / per_pixel < 0.5)
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

    /// The term is a few micrometres wide, so it only exists at resolutions
    /// that sample the film at a few micrometres. This is the property that
    /// decides whether a 1200-pixel render needs it at all.
    #[test]
    fn the_blur_is_a_no_op_below_the_film_s_blur() {
        // A 35 mm frame at 1200 px across: sampled every 30 µm.
        assert!(EmulsionBlur::measured(30.0).is_noop());
        // At 6000 px across: every 6 µm, where blue is nearly a pixel wide.
        assert!(!EmulsionBlur::measured(6.0).is_noop());
        // And at 12000: every 3 µm, where all three layers blur.
        let fine = EmulsionBlur::measured(3.0);
        assert!(!fine.is_noop());
        for sigma in fine.sigma_um {
            assert!(sigma / 3.0 >= 0.5);
        }
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
