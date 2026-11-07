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

use crate::model::{ScanModel, inverse3, table, tables};
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
/// Entries in [`ScanContext::neutral_rgb`], the density levels 0 to
/// `NEUTRAL_MAX_DENSITY` inclusive.
pub(crate) const NEUTRAL_ENTRIES: usize = NEUTRAL_STEPS + 1;

/// CIE standard illuminant D50 on the internal grid, 5 nm steps.
///
/// ISO 3664 specifies D50 for judging reflection prints, which is what this
/// model scans. Values are the CIE SPD, normalised only by the white-point
/// division in `scan`.
const D50_SPD: [f64; 71] = [
    24.49, 27.18, 29.87, 39.59, 49.31, 52.91, 56.51, 58.27, 60.03, 58.93, 57.82, 66.32, 74.83,
    81.04, 87.25, 88.93, 90.61, 90.99, 91.37, 93.24, 95.11, 93.54, 91.96, 93.84, 95.72, 96.17,
    96.61, 96.87, 97.13, 99.61, 102.10, 101.43, 100.75, 101.54, 102.32, 101.16, 100.00, 98.87,
    97.73, 98.33, 98.92, 96.21, 93.50, 95.59, 97.69, 98.48, 99.27, 99.16, 99.04, 97.38, 95.72,
    97.29, 98.86, 97.26, 95.67, 96.93, 98.19, 100.60, 103.00, 101.07, 99.13, 93.26, 87.38, 89.49,
    91.60, 92.25, 92.89, 84.87, 76.85, 81.68, 86.51,
];

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
        // D50: the viewing condition ISO 3664 specifies for reflection prints.
        let illuminant = Spectrum::new(
            crate::spectral::GRID_START_NM,
            crate::spectral::GRID_STEP_NM,
            D50_SPD.to_vec(),
        )
        .expect("the D50 table matches the internal grid");

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
    /// Build the context the renderer uses: the paper's dyes are measured.
    ///
    /// # Panics
    ///
    /// Cannot panic: the tables are compile-time constants on the internal grid.
    #[must_use]
    pub fn measured() -> Self {
        Self::new()
            .with_dyes(crate::measured::PAPER_DYES.map(|table| crate::measured::spectrum(&table)))
    }

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

    /// The paper's image dyes.
    #[must_use]
    pub fn dye(&self) -> &[Spectrum; 3] {
        &self.dye
    }

    /// The viewing illuminant.
    #[must_use]
    pub fn illuminant(&self) -> &Spectrum {
        &self.illuminant
    }

    /// The colour matching functions, one per axis.
    #[must_use]
    pub fn cmf(&self) -> &[Spectrum; 3] {
        &self.cmf
    }

    /// XYZ of paper white.
    #[must_use]
    pub fn white_xyz(&self) -> [f64; 3] {
        self.white_xyz
    }

    /// RGB of paper white.
    #[must_use]
    pub fn white_rgb(&self) -> [f64; 3] {
        self.white_rgb
    }

    /// RGB along the neutral axis, evenly spaced in density from zero to the
    /// span [`Self::model`] reports as `neutral_max_density`.
    #[must_use]
    pub fn neutral_rgb(&self) -> &[[f64; 3]] {
        &self.neutral_rgb
    }

    /// The constants this context integrates with, flattened for another backend.
    ///
    /// `None` when a table is not on the model's grid, which [`Self::new`] rules
    /// out but [`Self::with_dyes`] does not have to.
    #[must_use]
    pub fn model(&self) -> Option<ScanModel> {
        let inverse = inverse3(self.analytical_matrix());
        Some(ScanModel {
            analytical: inverse.unwrap_or([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]),
            clamped: inverse.is_some(),
            dye: tables(&self.dye)?,
            illuminant: table(&self.illuminant)?,
            cmf: tables(&self.cmf)?,
            matrix: XYZ_TO_SRGB,
            white_xyz: self.white_xyz,
            white_rgb: self.white_rgb,
            neutral: self.neutral_rgb.as_slice().try_into().ok()?,
            neutral_max_density: NEUTRAL_MAX_DENSITY,
            base_density: PAPER_BASE_DENSITY,
        })
    }

    /// Solve for the per-dye analytical densities behind a set of status densities.
    ///
    /// The characteristic curves report **status** densities: each channel is
    /// measured through a filter and contains contributions from all three dyes.
    /// The dye curves describe **analytical** absorption: one shape per dye,
    /// peak-normalised. Feeding status densities straight into the dye shapes
    /// double-counts the overlap, which is why a neutral print went black.
    ///
    /// The mixing matrix samples the dye curves at the status filter peaks
    /// (650/550/450 nm). Real status filters are broad; sampling their peaks is
    /// the documented approximation.
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

    fn reflectance(&self, status_density: [f64; 3]) -> Spectrum {
        let density_cmy = self.analytical(status_density);
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

/// Gaussian elimination with partial pivoting for the 3x3 unmixing solve.
pub(crate) fn solve3(mut matrix: [[f64; 3]; 3], mut rhs: [f64; 3]) -> Option<[f64; 3]> {
    for column in 0..3 {
        let pivot = (column..3)
            .max_by(|&a, &b| matrix[a][column].abs().total_cmp(&matrix[b][column].abs()))?;
        if matrix[pivot][column].abs() < 1e-9 {
            return None;
        }
        matrix.swap(column, pivot);
        rhs.swap(column, pivot);
        let pivot_row = matrix[column];
        let pivot_value = pivot_row[column];
        for row in (column + 1)..3 {
            let factor = matrix[row][column] / pivot_value;
            for (cell, value) in pivot_row.iter().enumerate().skip(column) {
                matrix[row][cell] -= factor * value;
            }
            rhs[row] -= factor * rhs[column];
        }
    }
    let mut solution = [0.0; 3];
    for row in (0..3).rev() {
        let mut sum = rhs[row];
        for (column, value) in solution.iter().enumerate().skip(row + 1) {
            sum -= matrix[row][column] * value;
        }
        solution[row] = sum / matrix[row][row];
    }
    Some(solution)
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
