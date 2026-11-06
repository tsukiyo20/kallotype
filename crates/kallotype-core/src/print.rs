//! Spectral printing: dye densities to paper layer exposures.
//!
//! Phase 0 printed by treating each channel's density as that channel's light
//! loss. That misses the reason colour negatives have orange masks and couplers:
//! a dye does not absorb in one channel, it absorbs over a band, and the paper's
//! three layers overlap as well.
//!
//! The chain is short and physical:
//!
//! ```text
//! D_cmy ──► T(λ) = 10^(-Σ d · absorption) ──► ∫ L(λ)·T(λ)·S_layer(λ) dλ ──► logE
//! ```
//!
//! Everything here is a **placeholder**: the dye and layer spectra are broad
//! Gaussians with plausible widths, not measurements. They are parameterised in
//! one place so phase 4 can replace them with digitised curves without touching
//! the arithmetic.

use kallotype_spectral::Spectrum;

use crate::spectral::{GRID_LEN, GRID_START_NM, GRID_STEP_NM};

/// One dye's absorption, or one paper layer's sensitivity, as a Gaussian band.
#[derive(Debug, Clone, Copy)]
struct Band {
    peak_nm: f64,
    width_nm: f64,
}

/// Cyan absorbs red, magenta absorbs green, yellow absorbs blue. The widths are
/// wide on purpose: that overlap *is* the crosstalk the scalar model lacks.
const DYE_BANDS: [Band; 3] = [
    Band {
        peak_nm: 650.0,
        width_nm: 55.0,
    },
    Band {
        peak_nm: 550.0,
        width_nm: 50.0,
    },
    Band {
        peak_nm: 450.0,
        width_nm: 55.0,
    },
];

/// The paper's three layers sit under the same three bands, for the same reason.
const PAPER_BANDS: [Band; 3] = [
    Band {
        peak_nm: 650.0,
        width_nm: 45.0,
    },
    Band {
        peak_nm: 550.0,
        width_nm: 40.0,
    },
    Band {
        peak_nm: 450.0,
        width_nm: 45.0,
    },
];

/// The spectral model of the enlarger and the paper.
#[derive(Debug, Clone)]
pub struct PrintContext {
    grid: Spectrum,
    dye: [Spectrum; 3],
    paper: [Spectrum; 3],
    reference: [f64; 3],
    /// The density the print balance is anchored on, kept so that replacing the
    /// spectra can recompute the anchor.
    reference_density: [f64; 3],
}

impl PrintContext {
    /// Build the context, anchoring the output on a reference negative density.
    ///
    /// The anchor is what makes the print balance solvable: everything is
    /// reported relative to the light the reference negative passes, so a
    /// mid-grey negative lands at log exposure 0 on every layer.
    ///
    /// # Panics
    ///
    /// Cannot panic: the grid is a valid constant.
    #[must_use]
    pub fn new(reference_density: [f64; 3]) -> Self {
        let grid = Spectrum::uniform(GRID_START_NM, GRID_STEP_NM, GRID_LEN)
            .expect("the internal grid is a valid constant");

        let dye: [Spectrum; 3] = DYE_BANDS.map(|band| gaussian(&grid, band));
        // Unit area, so the response to white light is 1.0 per layer.
        let paper: [Spectrum; 3] = PAPER_BANDS.map(|band| normalised(gaussian(&grid, band)));

        let mut context = Self {
            grid,
            dye,
            paper,
            reference: [1.0; 3],
            reference_density,
        };
        // Anchor on the *neutral* density at the reference level, so that grey
        // stays grey across the scale. The pipeline compensates for the small
        // residual at the actual (near-neutral) mid-grey density.
        let neutral_level =
            (reference_density[0] + reference_density[1] + reference_density[2]) / 3.0;
        context.reference = context.balanced([neutral_level; 3]);
        context
    }

    /// Replace only the dye spectra, keeping the paper layers.
    #[must_use]
    pub fn with_dyes(mut self, dye: [Spectrum; 3]) -> Self {
        self.dye = dye.map(|spectrum| spectrum.resampled(&self.grid));
        self.reference = self.balanced(self.reference_density);
        self
    }

    /// The gain the grey balance applies at a neutral density, per layer.
    ///
    /// A diagnostic: if real dyes are neutral by design, these gains should be
    /// close to 1 and the numerical balance is doing nothing.
    #[must_use]
    pub fn balance_gain(&self, neutral_density: f64) -> [f64; 3] {
        let response = self.response([neutral_density; 3]);
        let target = (response[0] * response[1] * response[2]).cbrt();
        std::array::from_fn(|layer| target / response[layer].max(1e-12))
    }

    /// Replace the placeholder bands with measured spectra.
    ///
    /// The spectra are resampled onto the internal grid, so anything digitised
    /// on a uniform grid can be passed in. The reference response is recomputed,
    /// because the anchor depends on the dyes.
    #[must_use]
    pub fn with_spectra(mut self, dye: [Spectrum; 3], paper: [Spectrum; 3]) -> Self {
        self.dye = dye.map(|spectrum| spectrum.resampled(&self.grid));
        self.paper = paper.map(|spectrum| spectrum.resampled(&self.grid));
        self.reference = self.balanced(self.reference_density);
        self
    }

    /// The wavelength grid.
    #[must_use]
    pub fn grid(&self) -> &Spectrum {
        &self.grid
    }

    /// log10 of the paper's layer response, relative to the reference negative.
    #[must_use]
    pub fn expose(&self, density_cmy: [f64; 3]) -> [f64; 3] {
        let response = self.balanced(density_cmy);
        std::array::from_fn(|layer| {
            let ratio = response[layer] / self.reference[layer].max(1e-12);
            ratio.max(1e-10).log10()
        })
    }

    /// Grey balance.
    ///
    /// Overlapping dye bands make a neutral negative transmit a coloured
    /// spectrum, and the paper's own overlapping sensitivities do not cancel it.
    /// Real products solve this with dye and coupler design; a placeholder model
    /// has to solve it numerically, or every neutral prints green.
    ///
    /// The correction is defined on the neutral axis only: scale each layer so
    /// that a density triple equal on all three channels responds equally on all
    /// three layers. Colour casts caused by *unequal* densities survive, because
    /// that is the crosstalk the model is here to express.
    fn balanced(&self, density_cmy: [f64; 3]) -> [f64; 3] {
        let response = self.response(density_cmy);
        let mean = (density_cmy[0] + density_cmy[1] + density_cmy[2]) / 3.0;
        let neutral = self.response([mean; 3]);
        let target = (neutral[0] * neutral[1] * neutral[2]).cbrt();

        std::array::from_fn(|layer| {
            let scale = target / neutral[layer].max(1e-12);
            response[layer] * scale
        })
    }

    fn response(&self, density_cmy: [f64; 3]) -> [f64; 3] {
        // Allocation-free on purpose: this runs once per pixel, and cloning a
        // spectrum here measured 20x slower than the rest of the render.
        let step = self.grid.step_nm();
        let mut response = [0.0_f64; 3];
        for wavelength_index in 0..self.grid.len() {
            let density: f64 = density_cmy
                .iter()
                .zip(&self.dye)
                .map(|(value, dye)| value * dye.values()[wavelength_index])
                .sum();
            // exp2 is markedly cheaper than powf and this runs per wavelength
            // per pixel: 10^-d = 2^(-d * log2 10).
            let transmitted = (-density * std::f64::consts::LOG2_10).exp2();
            for (value, paper) in response.iter_mut().zip(&self.paper) {
                *value += paper.values()[wavelength_index] * transmitted;
            }
        }
        for value in &mut response {
            *value *= step;
        }
        response
    }
}

fn gaussian(grid: &Spectrum, band: Band) -> Spectrum {
    let mut spectrum = Spectrum::filled(grid.clone(), 0.0);
    for (index, value) in spectrum.values_mut().iter_mut().enumerate() {
        let wavelength = grid.start_nm() + grid.step_nm() * index as f64;
        let z = (wavelength - band.peak_nm) / band.width_nm;
        *value = (-0.5 * z * z).exp();
    }
    spectrum
}

fn normalised(mut spectrum: Spectrum) -> Spectrum {
    let area: f64 = spectrum.values().iter().sum::<f64>() * spectrum.step_nm();
    if area > 0.0 {
        for value in spectrum.values_mut() {
            *value /= area;
        }
    }
    spectrum
}

#[cfg(test)]
mod tests {
    use super::*;

    fn reference_density() -> [f64; 3] {
        [1.2, 1.1, 1.0]
    }

    #[test]
    fn the_neutral_reference_lands_at_zero() {
        let context = PrintContext::new(reference_density());
        let level =
            (reference_density()[0] + reference_density()[1] + reference_density()[2]) / 3.0;
        for log_e in context.expose([level; 3]) {
            assert!(log_e.abs() < 1e-9, "{log_e}");
        }
    }

    #[test]
    fn the_reference_negative_is_near_zero() {
        let context = PrintContext::new(reference_density());
        // The anchor is neutral grey, so the slightly non-neutral reference
        // negative sits within a fraction of a stop. The pipeline subtracts the
        // remainder when it solves the print balance.
        for log_e in context.expose(reference_density()) {
            assert!(log_e.abs() < 0.15, "{log_e}");
        }
    }

    #[test]
    fn more_density_means_less_light_on_every_layer() {
        let context = PrintContext::new(reference_density());
        let base = context.expose(reference_density());
        let denser = context.expose([1.6, 1.1, 1.0]);
        assert!(denser[0] < base[0], "{denser:?}");
    }

    #[test]
    fn measured_spectra_replace_the_placeholders() {
        let context = PrintContext::new(reference_density());
        let baseline = context.expose([1.0, 0.5, 0.2]);

        // Narrow bands are a different physical world: less overlap, less
        // crosstalk, so the numbers must move.
        let grid = context.grid().clone();
        let narrow: [Spectrum; 3] = [450.0, 550.0, 650.0].map(|peak| {
            let mut spectrum = Spectrum::filled(grid.clone(), 0.0);
            for (index, value) in spectrum.values_mut().iter_mut().enumerate() {
                let wavelength = grid.start_nm() + grid.step_nm() * index as f64;
                *value = (-0.5 * ((wavelength - peak) / 12.0).powi(2)).exp();
            }
            spectrum
        });
        let replaced = PrintContext::new(reference_density()).with_spectra(narrow.clone(), narrow);
        let moved = replaced.expose([1.0, 0.5, 0.2]);
        let difference: f64 = baseline
            .iter()
            .zip(&moved)
            .map(|(a, b)| (a - b).abs())
            .sum();
        assert!(difference > 1e-3, "replacing the spectra changed nothing");
    }

    #[test]
    fn neutral_densities_stay_neutral() {
        let context = PrintContext::new(reference_density());
        // A grey scale across the useful density range.
        for step in 0..=12 {
            let density = 0.2 + 0.15 * f64::from(step);
            let log_e = context.expose([density; 3]);
            let spread = log_e.iter().copied().fold(f64::NEG_INFINITY, f64::max)
                - log_e.iter().copied().fold(f64::INFINITY, f64::min);
            assert!(
                spread < 1e-9,
                "grey {density} drifts by {spread}: {log_e:?}"
            );
        }
    }

    #[test]
    fn dyes_leak_into_neighbouring_layers() {
        let context = PrintContext::new(reference_density());
        let base = context.expose(reference_density());

        // Pure cyan: it should darken the red layer most...
        let cyan = context.expose([1.7, 1.1, 1.0]);
        let red_drop = base[0] - cyan[0];
        let green_drop = base[1] - cyan[1];
        assert!(
            red_drop > green_drop,
            "red {red_drop} vs green {green_drop}"
        );

        // ...but it must also move the other layers. That coupling is exactly
        // what the scalar print model could not express.
        assert!(green_drop.abs() > 1e-4, "no crosstalk: {green_drop}");
    }
}
