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
//! The mask is the part that is not a constant. An unexposed colour negative is
//! orange because the cyan layer carries a coloured coupler that absorbs blue;
//! that coupler is consumed wherever cyan dye is made, so the mask and the dye's
//! unwanted absorption cancel. [`PrintContext::with_masking`] is that term — see
//! [`Masking`].
//!
//! Everything here is a **placeholder**: the dye and layer spectra are broad
//! Gaussians with plausible widths, not measurements. They are parameterised in
//! one place so phase 4 can replace them with digitised curves without touching
//! the arithmetic. The mask is the exception: `with_base_density` takes the
//! measured one, which is why masking couplers could be modelled before the dyes
//! they compensate.

use kallotype_spectral::Spectrum;

use crate::model::{PrintModel, inverse3, table, tables};
use crate::scan::solve3;

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

/// Filter pack bands: yellow removes blue, magenta removes green, cyan removes
/// red. Wider than a real dichroic filter, and a placeholder.
const FILTER_BANDS: [Band; 3] = [
    Band {
        peak_nm: 450.0,
        width_nm: 55.0,
    },
    Band {
        peak_nm: 550.0,
        width_nm: 50.0,
    },
    Band {
        peak_nm: 650.0,
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

/// Masking couplers: the coloured coupler that is destroyed as the dye forms.
///
/// A colour negative is not three independent layers. The cyan dye absorbs some
/// blue and green that it should not, so the cyan layer carries a **coloured
/// coupler** — an orange mask — that absorbs blue and is consumed wherever cyan
/// dye is made. The two errors then subtract: where the cyan dye is dense the
/// mask is gone, and where it is thin the mask is there to take its place.
///
/// That is why an unexposed colour negative is orange, and why the orange goes
/// away as the frame is exposed. [`PrintContext::with_base_density`] adds the
/// mask as a constant; this is the term that makes it behave.
///
/// The strength is per layer because the mask does not have to belong to the
/// cyan one alone — in practice the orange mask does, which is the default.
#[derive(Debug, Clone, Copy)]
pub struct Masking {
    /// Fraction of the base density each layer destroys at its reference density.
    pub strength: [f64; 3],
    /// Density at which a layer has destroyed all the mask it can.
    pub reference_density: f64,
}

impl Default for Masking {
    fn default() -> Self {
        Self {
            strength: [1.0, 0.0, 0.0],
            reference_density: 2.0,
        }
    }
}

impl Masking {
    /// How much of the mask survives, given the three analytical densities.
    #[must_use]
    pub fn surviving(&self, density_cmy: [f64; 3]) -> f64 {
        let reference = self.reference_density.max(1e-9);
        let removed: f64 = density_cmy
            .iter()
            .zip(&self.strength)
            .map(|(density, strength)| strength * (density / reference).clamp(0.0, 1.0))
            .sum();
        (1.0 - removed).clamp(0.0, 1.0)
    }
}

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
    /// Enlarger filter pack, in Kodak colour-correction units for yellow, magenta
    /// and cyan. Cyan is almost always zero in a colour head.
    filters: [f64; 3],
    /// The three filter absorption bands: yellow removes blue, magenta removes
    /// green, cyan removes red. Placeholders, like the dyes.
    filter_bands: [Spectrum; 3],
    /// The enlarger's light source. Equal-energy until a real one is measured.
    illuminant: Spectrum,
    /// Density of the unexposed, processed film: base, fog and the colour mask.
    /// Added to the dye densities before the transmittance is computed.
    base_density: Option<Spectrum>,
    /// How much of that base density the couplers destroy as dye forms.
    masking: Option<Masking>,
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
        // Built before the struct literal, because `grid` is moved into it.
        let filter_bands: [Spectrum; 3] = FILTER_BANDS.map(|band| gaussian(&grid, band));
        let illuminant = Spectrum::filled(grid.clone(), 1.0);

        let mut context = Self {
            grid,
            dye,
            paper,
            reference: [1.0; 3],
            reference_density,
            filters: [0.0; 3],
            filter_bands,
            illuminant,
            base_density: None,
            masking: None,
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

    /// Set the enlarger filter pack, in Kodak colour-correction units.
    #[must_use]
    pub fn with_filters(mut self, filters: [f64; 3]) -> Self {
        self.filters = filters;
        self.reference = self.balanced(self.reference_density);
        self
    }

    /// Solve for the filter pack that makes a neutral negative print neutral.
    ///
    /// The filters change the ratio of the three layer responses, which is exactly
    /// what a printer adjusts with test strips. Two unknowns, two ratios, so a
    /// coarse grid followed by a refinement is enough and is easier to trust than
    /// a gradient step on a function with clamps in it.
    #[must_use]
    pub fn solve_filters(&self, density: f64) -> [f64; 3] {
        let spread = |candidate: Self| {
            let response = candidate.response([density; 3]);
            let target = (response[0] * response[1] * response[2]).cbrt();
            let gains: [f64; 3] = std::array::from_fn(|i| target / response[i].max(1e-12));
            gains.iter().copied().fold(f64::NEG_INFINITY, f64::max)
                - gains.iter().copied().fold(f64::INFINITY, f64::min)
        };

        let mut best = (f64::INFINITY, [0.0; 3]);
        let mut step = 10.0_f64;
        let mut centre = [0.0_f64; 3];
        for _ in 0..4 {
            for yellow in 0..=20 {
                for magenta in 0..=20 {
                    let candidate = [
                        centre[0] + (f64::from(yellow) - 10.0) * step,
                        centre[1] + (f64::from(magenta) - 10.0) * step,
                        0.0,
                    ]
                    .map(|value| value.max(0.0));
                    let value = spread(self.clone().with_filters(candidate));
                    if value < best.0 {
                        best = (value, candidate);
                    }
                }
            }
            centre = best.1;
            step /= 5.0;
        }
        best.1
    }

    /// Build the context the renderer uses: every spectrum measured.
    ///
    /// The dyes, the paper's layers and the mask are the digitised curves from
    /// `crate::measured`; the mask is coupled, so it is consumed where the cyan
    /// dye forms. This is the model, and [`Self::new`] is what it is compared
    /// against.
    ///
    /// # Panics
    ///
    /// Cannot panic: the tables are compile-time constants on the internal grid.
    #[must_use]
    pub fn measured(reference_density: [f64; 3]) -> Self {
        Self::new(reference_density)
            .with_spectra(
                crate::measured::FILM_DYES.map(|table| crate::measured::spectrum(&table)),
                crate::measured::PAPER_LAYERS.map(|table| crate::measured::spectrum(&table)),
            )
            .with_base_density(crate::measured::spectrum(&crate::measured::FILM_MASK))
            .with_masking(Masking::default())
    }

    /// Add the film's minimum density: base, fog and the orange mask.
    ///
    /// The published dye curves have D-min subtracted, so the mask is not in
    /// them. Without it a neutral negative does not print neutral, and the grey
    /// balance is left compensating for a physical layer that was removed from
    /// the data.
    #[must_use]
    pub fn with_base_density(mut self, base: Spectrum) -> Self {
        let base = base.resampled(&self.grid);
        self.base_density = Some(base);
        self.reference = self.balanced(self.reference_density);
        self
    }

    /// Let the base density be destroyed as the dyes form.
    ///
    /// Without this the mask is a constant, which is what an unexposed frame
    /// looks like and not what an exposed one does.
    #[must_use]
    pub fn with_masking(mut self, masking: Masking) -> Self {
        self.masking = Some(masking);
        self.reference = self.balanced(self.reference_density);
        self
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

    /// Status density to analytical density.
    ///
    /// The characteristic curves are measured through status filters, so each
    /// channel already contains all three dyes. The dye curves are per-dye
    /// shapes. Feeding one into the other double-counts the overlap; the same
    /// correction the scan needed applies here.
    ///
    /// The system depends only on the dyes, so it is built once per call and
    /// inverted once per render — see [`Self::model`].
    fn analytical_matrix(&self) -> [[f64; 3]; 3] {
        let probes = [650.0, 550.0, 450.0];
        let mut matrix = [[0.0_f64; 3]; 3];
        for (row, wavelength) in probes.iter().enumerate() {
            for (column, dye) in self.dye.iter().enumerate() {
                matrix[row][column] = dye.interpolate(*wavelength);
            }
        }
        matrix
    }

    fn analytical(&self, status: [f64; 3]) -> [f64; 3] {
        solve3(self.analytical_matrix(), status)
            .map(|values| values.map(|value| value.max(0.0)))
            .unwrap_or(status)
    }

    /// The constants this context integrates with, flattened for another backend.
    ///
    /// `None` when a table is not on the model's grid, which
    /// [`Self::new`] rules out but [`Self::with_spectra`] does not have to.
    #[must_use]
    pub fn model(&self) -> Option<PrintModel> {
        let inverse = inverse3(self.analytical_matrix());
        // No base density prints as a zero mask, and no masking prints as zero
        // strengths: the surviving fraction is then one, so the mask is a
        // constant, which is what masking off means.
        Some(PrintModel {
            analytical: inverse.unwrap_or([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]),
            clamped: inverse.is_some(),
            dye: tables(&self.dye)?,
            paper: tables(&self.paper)?,
            illuminant: table(&self.illuminant)?,
            mask: match &self.base_density {
                Some(base) => table(base)?,
                None => [0.0; GRID_LEN],
            },
            masking: self.masking.map_or([0.0; 3], |masking| masking.strength),
            masking_reference: self
                .masking
                .map_or(1.0, |masking| masking.reference_density),
            filters: self.filters,
            filter_bands: tables(&self.filter_bands)?,
            reference: self.reference,
        })
    }

    fn response(&self, status_density: [f64; 3]) -> [f64; 3] {
        let density_cmy = self.analytical(status_density);
        // Allocation-free on purpose: this runs once per pixel, and cloning a
        // spectrum here measured 20x slower than the rest of the render.
        let step = self.grid.step_nm();
        let mut response = [0.0_f64; 3];
        for wavelength_index in 0..self.grid.len() {
            // The mask is present in the unexposed film and consumed where the
            // dyes form, which is the masking coupler doing its job.
            let mask = match (&self.base_density, &self.masking) {
                (Some(base), Some(masking)) => {
                    base.values()[wavelength_index] * masking.surviving(density_cmy)
                }
                (Some(base), None) => base.values()[wavelength_index],
                (None, _) => 0.0,
            };
            let mut density: f64 = mask;
            density += density_cmy
                .iter()
                .zip(&self.dye)
                .map(|(value, dye)| value * dye.values()[wavelength_index])
                .sum::<f64>();
            // exp2 is markedly cheaper than powf and this runs per wavelength
            // per pixel: 10^-d = 2^(-d * log2 10).
            let mut filter = 0.0;
            for (cc, band) in self.filters.iter().zip(&self.filter_bands) {
                filter += cc * band.values()[wavelength_index] / 100.0;
            }
            let light = self.illuminant.values()[wavelength_index];
            let transmitted = (-(density + filter) * std::f64::consts::LOG2_10).exp2() * light;
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

/// With no coupling the base density is a constant: an unexposed frame and a
/// fully exposed one wear the same mask.
#[test]
fn without_masking_the_base_density_is_constant() {
    let masking = Masking::default();
    assert!((masking.surviving([0.0; 3]) - 1.0).abs() < 1e-12);
    assert!((masking.surviving([2.0, 0.0, 0.0]) - 0.0).abs() < 1e-12);
    assert!((masking.surviving([1.0, 0.0, 0.0]) - 0.5).abs() < 1e-12);
}

/// The mask belongs to the cyan layer by default: developing the magenta or
/// the yellow layer must leave it alone.
#[test]
fn only_the_layer_that_owns_the_mask_destroys_it() {
    let masking = Masking::default();
    assert!((masking.surviving([0.0, 2.0, 0.0]) - 1.0).abs() < 1e-12);
    assert!((masking.surviving([0.0, 0.0, 2.0]) - 1.0).abs() < 1e-12);
}

/// The point of the model: as cyan dye forms, the mask releases the blue it
/// was absorbing, so the layer's blue absorption stops growing.
#[test]
fn the_mask_gives_blue_back_as_cyan_forms() {
    let grid = Spectrum::uniform(380.0, 5.0, 71).unwrap();
    // A mask that absorbs blue only.
    let mut base = Spectrum::filled(grid.clone(), 0.0);
    for (index, value) in base.values_mut().iter_mut().enumerate() {
        let wavelength = grid.start_nm() + grid.step_nm() * index as f64;
        *value = 0.6 * (-0.5 * ((wavelength - 450.0) / 25.0).powi(2)).exp();
    }
    let context = PrintContext::new([1.0; 3]).with_base_density(base);
    let masked = context.clone().with_masking(Masking::default());
    // Blue is channel 2 of the scan, but `expose` returns paper response;
    // compare the plain context with the masked one at the same density.
    // `with_masking` re-anchors on the reference density, so the absolute
    // values move; what must not move is the *gain* from forming cyan dye.
    let plain_gain = context.expose([2.0, 0.0, 0.0])[2] - context.expose([0.0; 3])[2];
    let masked_gain = masked.expose([2.0, 0.0, 0.0])[2] - masked.expose([0.0; 3])[2];
    assert!(
        masked_gain > plain_gain,
        "the mask must give blue back: {masked_gain} vs {plain_gain}"
    );
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
