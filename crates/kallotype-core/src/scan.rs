//! Spectral scanning: print densities to output colour.
//!
//! The last non-physical step. Phase 0 turned a print density straight into a
//! channel value; this turns it into a spectrum, then into a colour:
//!
//! ```text
//! D_cmy ──► R(λ) = 10^(-Σ d·dye - base) ──► R(λ)·L(λ) ──► XYZ ──► linear RGB
//! ```
//!
//! The observer is the CIE 1931 2° fit from `kallotype-spectral`; the illuminant
//! is equal-energy and the dyes are the same placeholder bands as the print. All
//! three are labelled where they are defined, and all three are replaceable
//! without touching this arithmetic.

use kallotype_spectral::Spectrum;
use kallotype_spectral::sensor::cie1931_xyz;

use crate::spectral::{GRID_LEN, GRID_START_NM, GRID_STEP_NM};

/// A dye's absorption band, as a Gaussian.
#[derive(Debug, Clone, Copy)]
struct Band {
    peak_nm: f64,
    width_nm: f64,
}

/// The image dyes in the paper: cyan, magenta, yellow, at the usual primaries.
const PAPER_DYES: [Band; 3] = [
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

/// Base density of unexposed paper: a little light is always lost.
const PAPER_BASE_DENSITY: f64 = 0.06;

/// Density range covered by the grey-balance table.
const NEUTRAL_MAX_DENSITY: f64 = 3.0;
/// Entries in the grey-balance table.
const NEUTRAL_STEPS: usize = 32;

/// XYZ (D65) to linear sRGB, the standard matrix.
const XYZ_TO_SRGB: [[f64; 3]; 3] = [
    [3.240_454_2, -1.537_138_5, -0.498_531_4],
    [-0.969_266_0, 1.876_010_8, 0.041_556_0],
    [0.055_643_4, -0.204_025_9, 1.057_225_2],
];

/// The spectral model of the scan.
#[derive(Debug, Clone)]
pub struct ScanContext {
    grid: Spectrum,
    dye: [Spectrum; 3],
    illuminant: Spectrum,
    cmf: [Spectrum; 3],
    /// XYZ of paper white, used to normalise so that white prints at 1.0.
    white_xyz: [f64; 3],
    /// RGB of paper white after the matrix, so white divides out to 1.0.
    white_rgb: [f64; 3],
    /// RGB of a neutral density at evenly spaced levels. Used for grey balance,
    /// for the same reason the print needs one: overlapping dyes do not cancel.
    neutral_rgb: Vec<[f64; 3]>,
}

impl ScanContext {
    /// Build the context on the internal grid.
    ///
    /// # Panics
    ///
    /// Cannot panic: the grid is a valid constant.
    #[must_use]
    pub fn new() -> Self {
        let grid = Spectrum::uniform(GRID_START_NM, GRID_STEP_NM, GRID_LEN)
            .expect("the internal grid is a valid constant");

        let dye: [Spectrum; 3] = PAPER_DYES.map(|band| gaussian(&grid, band));
        // Equal-energy illuminant: a placeholder, and the reason the output's
        // white point is not a real viewing condition yet.
        let illuminant = Spectrum::filled(grid.clone(), 1.0);

        let cmf: [Spectrum; 3] = std::array::from_fn(|axis| {
            let mut spectrum = Spectrum::filled(grid.clone(), 0.0);
            for (index, value) in spectrum.values_mut().iter_mut().enumerate() {
                let wavelength = GRID_START_NM + GRID_STEP_NM * index as f64;
                *value = cie1931_xyz(wavelength)[axis].max(0.0);
            }
            spectrum
        });

        let mut context = Self {
            grid,
            dye,
            illuminant,
            cmf,
            white_xyz: [1.0; 3],
            white_rgb: [1.0; 3],
            neutral_rgb: Vec::new(),
        };

        context.recompute();
        context
    }

    /// Apply the XYZ-to-RGB matrix without normalisation.
    fn matrix(&self, xyz: [f64; 3]) -> [f64; 3] {
        let mut rgb = [0.0_f64; 3];
        for (row, value) in XYZ_TO_SRGB.iter().zip(rgb.iter_mut()) {
            *value = row[0] * xyz[0] + row[1] * xyz[1] + row[2] * xyz[2];
        }
        rgb
    }

    fn normalised_xyz(&self, density_cmy: [f64; 3]) -> [f64; 3] {
        let xyz = self.xyz(density_cmy);
        std::array::from_fn(|axis| xyz[axis] / self.white_xyz[axis].max(1e-12))
    }

    /// Grey balance, interpolated on the neutral axis.
    fn balance(&self, rgb: [f64; 3], mean_density: f64) -> [f64; 3] {
        if self.neutral_rgb.is_empty() {
            return rgb;
        }
        let position = (mean_density / NEUTRAL_MAX_DENSITY * NEUTRAL_STEPS as f64)
            .clamp(0.0, NEUTRAL_STEPS as f64);
        let low = position.floor() as usize;
        let high = (low + 1).min(NEUTRAL_STEPS);
        let fraction = position - low as f64;

        let neutral: [f64; 3] = std::array::from_fn(|axis| {
            self.neutral_rgb[low][axis] * (1.0 - fraction) + self.neutral_rgb[high][axis] * fraction
        });
        let target = (neutral[0].max(1e-12) * neutral[1].max(1e-12) * neutral[2].max(1e-12)).cbrt();
        std::array::from_fn(|axis| rgb[axis] * target / neutral[axis].max(1e-12))
    }

    /// Replace the placeholder image dyes with measured spectra.
    ///
    /// White, the neutral-axis table and every derived quantity are recomputed,
    /// because all three depend on the dyes.
    #[must_use]
    pub fn with_dyes(mut self, dye: [Spectrum; 3]) -> Self {
        self.dye = dye.map(|spectrum| spectrum.resampled(&self.grid));
        self.recompute();
        self
    }

    /// Recompute everything that depends on the dye spectra.
    fn recompute(&mut self) {
        self.white_xyz = self.xyz([0.0; 3]);
        self.white_rgb = self.matrix([1.0; 3]);
        self.neutral_rgb = (0..=NEUTRAL_STEPS)
            .map(|index| {
                let density = NEUTRAL_MAX_DENSITY * index as f64 / NEUTRAL_STEPS as f64;
                let rgb = self.matrix(self.normalised_xyz([density; 3]));
                std::array::from_fn(|axis| rgb[axis] / self.white_rgb[axis].max(1e-12))
            })
            .collect();
    }

    /// The wavelength grid.
    #[must_use]
    pub fn grid(&self) -> &Spectrum {
        &self.grid
    }

    fn reflectance(&self, density_cmy: [f64; 3]) -> Spectrum {
        let step = self.grid.step_nm();
        let mut reflectance = self.grid.clone();
        for (index, value) in reflectance.values_mut().iter_mut().enumerate() {
            let mut density = PAPER_BASE_DENSITY;
            for (value, dye) in density_cmy.iter().zip(&self.dye) {
                density += value * dye.values()[index];
            }
            *value = (-density * std::f64::consts::LOG2_10).exp2();
        }
        let _ = step;
        reflectance
    }

    fn xyz(&self, density_cmy: [f64; 3]) -> [f64; 3] {
        let reflectance = self.reflectance(density_cmy);
        let step = self.grid.step_nm();
        let mut xyz = [0.0_f64; 3];
        for (index, reflectance_value) in reflectance.values().iter().enumerate() {
            let light = reflectance_value * self.illuminant.values()[index];
            for (value, cmf) in xyz.iter_mut().zip(&self.cmf) {
                *value += light * cmf.values()[index];
            }
        }
        for value in &mut xyz {
            *value *= step;
        }
        xyz
    }

    /// Linear-light RGB for a set of print densities.
    ///
    /// White is normalised to 1.0 per channel and the result is clamped to
    /// `[0, 1]`; the paper cannot reflect more than it receives.
    #[must_use]
    pub fn scan(&self, density_cmy: [f64; 3]) -> [f64; 3] {
        let rgb = self.matrix(self.normalised_xyz(density_cmy));
        let white_relative: [f64; 3] =
            std::array::from_fn(|axis| rgb[axis] / self.white_rgb[axis].max(1e-12));
        let mean = (density_cmy[0] + density_cmy[1] + density_cmy[2]) / 3.0;
        let balanced = self.balance(white_relative, mean);
        balanced.map(|value| value.clamp(0.0, 1.0))
    }
}

impl Default for ScanContext {
    fn default() -> Self {
        Self::new()
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paper_white_maps_to_one() {
        let context = ScanContext::new();
        let rgb = context.scan([0.0; 3]);
        for channel in rgb {
            assert!((channel - 1.0).abs() < 0.01, "white scans at {channel}");
        }
    }

    #[test]
    fn measured_dyes_replace_the_placeholders() {
        let baseline = ScanContext::new().scan([1.0, 0.6, 0.3]);
        let grid = ScanContext::new().grid().clone();
        let narrow: [Spectrum; 3] = [450.0, 550.0, 650.0].map(|peak| {
            let mut spectrum = Spectrum::filled(grid.clone(), 0.0);
            for (index, value) in spectrum.values_mut().iter_mut().enumerate() {
                let wavelength = grid.start_nm() + grid.step_nm() * index as f64;
                *value = (-0.5 * ((wavelength - peak) / 12.0).powi(2)).exp();
            }
            spectrum
        });
        let replaced = ScanContext::new().with_dyes(narrow).scan([1.0, 0.6, 0.3]);
        let difference: f64 = baseline
            .iter()
            .zip(&replaced)
            .map(|(a, b)| (a - b).abs())
            .sum();
        assert!(difference > 1e-3, "replacing the dyes changed nothing");
    }

    #[test]
    fn neutral_densities_scan_neutral() {
        let context = ScanContext::new();
        for step in 1..=10 {
            let density = 0.15 * f64::from(step);
            let rgb = context.scan([density; 3]);
            let spread = rgb.iter().copied().fold(f64::NEG_INFINITY, f64::max)
                - rgb.iter().copied().fold(f64::INFINITY, f64::min);
            assert!(spread < 0.02, "grey {density} drifts by {spread}: {rgb:?}");
        }
    }

    #[test]
    fn more_density_means_darker() {
        let context = ScanContext::new();
        let light = context.scan([0.2; 3]);
        let dark = context.scan([1.5; 3]);
        for channel in 0..3 {
            assert!(dark[channel] < light[channel]);
        }
    }
}
