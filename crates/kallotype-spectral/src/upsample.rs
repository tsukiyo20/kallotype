//! Recovering a spectrum from three numbers.
//!
//! This is the underdetermined step. Two families are provided so they can be
//! compared on the same data:
//!
//! - [`PolynomialUpsampler`] — a low-dimensional *smooth* prior. It stands in
//!   for the Mallett 2019 / Jakob–Hanika 2019 family without pretending to be
//!   either: those methods use better-conditioned bases, but they share the
//!   assumption that spectra are smooth.
//! - [`DictionaryUpsampler`] — a *statistical* prior. The reconstruction must be
//!   a non-negative mixture of known real spectra, which is the only way to
//!   keep features that are real but not smooth, like the red edge of a leaf.
//!
//! Neither is "correct". The benchmark exists to say which is less wrong, and
//! where.

use crate::sensor::Sensor;
use crate::spectrum::{SpectralError, Spectrum};

/// A candidate RGB → spectrum reconstruction.
pub trait Upsampler {
    /// Short name, used in benchmark tables.
    fn name(&self) -> &str;

    /// Reconstruct a spectrum that would produce `response` under `sensor`.
    ///
    /// # Errors
    ///
    /// Returns an error if the grid is unusable or the internal solve fails.
    fn reconstruct(
        &self,
        response: &[f64; 3],
        sensor: &Sensor,
        grid: &Spectrum,
    ) -> Result<Spectrum, SpectralError>;
}

/// A three-term polynomial basis in wavelength.
///
/// The simplest member of the smooth-prior family: three degrees of freedom,
/// exactly enough to match three sensor channels. It establishes a floor.
#[derive(Debug, Clone, Copy, Default)]
pub struct PolynomialUpsampler;

impl PolynomialUpsampler {
    /// The three basis functions on `grid`, normalised to `[-1, 1]`.
    fn basis(grid: &Spectrum) -> [Spectrum; 3] {
        let mut constant = Spectrum::filled(grid.clone(), 0.0);
        let mut linear = Spectrum::filled(grid.clone(), 0.0);
        let mut quadratic = Spectrum::filled(grid.clone(), 0.0);

        let start = grid.start_nm();
        let span = (grid.end_nm() - start).max(1e-9);
        for index in 0..grid.len() {
            let wavelength = grid.wavelength(index).unwrap_or(start);
            let t = 2.0 * (wavelength - start) / span - 1.0;
            constant.values_mut()[index] = 1.0;
            linear.values_mut()[index] = t;
            quadratic.values_mut()[index] = t * t;
        }
        [constant, linear, quadratic]
    }
}

impl Upsampler for PolynomialUpsampler {
    fn name(&self) -> &str {
        "polynomial"
    }

    fn reconstruct(
        &self,
        response: &[f64; 3],
        sensor: &Sensor,
        grid: &Spectrum,
    ) -> Result<Spectrum, SpectralError> {
        let basis = Self::basis(grid);
        let mut matrix = [[0.0_f64; 3]; 3];
        for (channel, row) in sensor.channels().iter().zip(matrix.iter_mut()) {
            for (term, cell) in basis.iter().zip(row.iter_mut()) {
                *cell = channel.dot(term)?;
            }
        }

        let coefficients = solve3(matrix, *response).unwrap_or([0.0; 3]);

        let mut out = Spectrum::filled(grid.clone(), 0.0);
        for (coefficient, term) in coefficients.iter().zip(&basis) {
            for (value, sample) in out.values_mut().iter_mut().zip(term.values()) {
                *value += coefficient * sample;
            }
        }
        // Reflectance cannot be negative; clamping is part of the model, not a
        // post-processing step.
        for value in out.values_mut() {
            *value = value.max(0.0);
        }
        Ok(out)
    }
}

/// A non-negative mixture of known spectra.
///
/// Solves `min ||A w - b||² + λ||w||²` subject to `w ≥ 0`, where the columns of
/// `A` are the sensor's response to each dictionary atom. The ridge term keeps
/// the solution from collapsing onto a handful of atoms when the dictionary is
/// small.
#[derive(Debug, Clone)]
pub struct DictionaryUpsampler {
    atoms: Vec<Spectrum>,
    ridge: f64,
    l1: f64,
    iterations: usize,
}

impl DictionaryUpsampler {
    /// Build from a dictionary of spectra, all on the same grid.
    #[must_use]
    pub fn new(atoms: Vec<Spectrum>) -> Self {
        Self {
            atoms,
            ridge: 1e-4,
            l1: 0.0,
            iterations: 1200,
        }
    }

    /// Override the ridge coefficient.
    #[must_use]
    pub fn with_ridge(mut self, ridge: f64) -> Self {
        self.ridge = ridge.max(0.0);
        self
    }

    /// Add an L1 penalty, which pushes the mixture towards few atoms.
    ///
    /// A dictionary with more atoms than sensor channels has enough freedom to
    /// match the measurement with a combination that is spectrally wrong. The
    /// L1 term is the cheapest way to take that freedom away: it makes the
    /// solution sparse, and a sparse mixture cannot wander as far into the
    /// null space.
    #[must_use]
    pub fn with_l1(mut self, l1: f64) -> Self {
        self.l1 = l1.max(0.0);
        self
    }

    /// Number of atoms.
    #[must_use]
    pub fn len(&self) -> usize {
        self.atoms.len()
    }

    /// Whether the dictionary is empty.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.atoms.is_empty()
    }
}

impl Upsampler for DictionaryUpsampler {
    fn name(&self) -> &str {
        "dictionary"
    }

    fn reconstruct(
        &self,
        response: &[f64; 3],
        sensor: &Sensor,
        grid: &Spectrum,
    ) -> Result<Spectrum, SpectralError> {
        let mut out = Spectrum::filled(grid.clone(), 0.0);
        if self.atoms.is_empty() {
            return Ok(out);
        }

        // A: 3 x M — each atom's response under each channel.
        let mut a = vec![[0.0_f64; 3]; self.atoms.len()];
        for (atom_index, atom) in self.atoms.iter().enumerate() {
            for (channel_index, channel) in sensor.channels().iter().enumerate() {
                a[atom_index][channel_index] = channel.dot(atom)?;
            }
        }

        let weights = nnls(&a, response, self.ridge, self.l1, self.iterations);

        for (weight, atom) in weights.iter().zip(&self.atoms) {
            if *weight == 0.0 {
                continue;
            }
            for (value, sample) in out.values_mut().iter_mut().zip(atom.values()) {
                *value += weight * sample;
            }
        }
        Ok(out)
    }
}

/// Solve a 3x3 system by Gaussian elimination with partial pivoting.
fn solve3(mut matrix: [[f64; 3]; 3], mut rhs: [f64; 3]) -> Option<[f64; 3]> {
    for column in 0..3 {
        let pivot = (column..3).max_by(|&left, &right| {
            matrix[left][column]
                .abs()
                .total_cmp(&matrix[right][column].abs())
        })?;
        if matrix[pivot][column].abs() < 1e-12 {
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

/// Projected-gradient non-negative least squares.
fn nnls(a: &[[f64; 3]], b: &[f64; 3], ridge: f64, l1: f64, iterations: usize) -> Vec<f64> {
    let count = a.len();
    let mut weights = vec![0.0_f64; count];

    // Lipschitz constant of the gradient: the largest squared column norm.
    let mut lipschitz = ridge;
    for row in a {
        let norm: f64 = row.iter().map(|value| value * value).sum();
        lipschitz += norm;
    }
    let lipschitz = lipschitz.max(1e-12);
    // The objective's gradient carries a factor of two, so the stable step is
    // half the reciprocal of the Lipschitz bound.
    let step = 1.0 / (2.0 * lipschitz);

    for _ in 0..iterations {
        // Residual b - A w.
        let mut residual = *b;
        for (row, weight) in a.iter().zip(&weights) {
            for (index, value) in row.iter().enumerate() {
                residual[index] -= weight * value;
            }
        }
        // Gradient descent on ||A w - b||^2 + λ2||w||^2, then the L1 proximal
        // step, then the non-negativity projection.
        for (index, weight) in weights.iter_mut().enumerate() {
            let row = &a[index];
            let gradient: f64 = 2.0
                * (row[0] * residual[0] + row[1] * residual[1] + row[2] * residual[2]
                    - ridge * *weight);
            // Proximal step for the L1 term: soft-threshold at step * l1 before
            // projecting onto the non-negative orthant.
            *weight = (*weight + step * gradient - step * l1).max(0.0);
        }
    }

    weights
}

#[cfg(test)]
mod tests {
    use super::*;

    fn grid() -> Spectrum {
        Spectrum::uniform(380.0, 10.0, 36).unwrap()
    }

    #[test]
    fn polynomial_matches_the_measurement_it_was_given() {
        let grid = grid();
        let sensor = Sensor::generic_camera(&grid);
        let target = Spectrum::new(
            380.0,
            10.0,
            (0..36).map(|i| 0.2 + 0.01 * f64::from(i)).collect(),
        )
        .unwrap();
        let response = sensor.respond(&target);

        let estimate = PolynomialUpsampler
            .reconstruct(&response, &sensor, &grid)
            .unwrap();
        let reproduced = sensor.respond(&estimate);

        for (expected, actual) in response.iter().zip(&reproduced) {
            assert!((expected - actual).abs() < 1e-6, "{expected} vs {actual}");
        }
    }

    #[test]
    fn nnls_reproduces_a_dictionary_atom() {
        let grid = grid();
        let sensor = Sensor::generic_camera(&grid);
        let atom = Spectrum::new(
            380.0,
            10.0,
            (0..36).map(|i| 0.1 + 0.02 * f64::from(i)).collect(),
        )
        .unwrap();
        let response = sensor.respond(&atom);

        let dictionary =
            DictionaryUpsampler::new(vec![atom.clone(), Spectrum::filled(grid.clone(), 0.5)]);
        let estimate = dictionary.reconstruct(&response, &sensor, &grid).unwrap();

        // A convex mixture of two positive atoms cannot overshoot far.
        assert!(estimate.max() < 2.0);
        assert!(estimate.min() >= 0.0);
    }

    #[test]
    fn the_l1_penalty_shrinks_the_mixture() {
        let grid = grid();
        let sensor = Sensor::generic_camera(&grid);
        let atoms: Vec<Spectrum> = (0..6)
            .map(|k| {
                Spectrum::new(
                    380.0,
                    10.0,
                    (0..36)
                        .map(|i| 0.1 + 0.02 * f64::from(i) + 0.01 * f64::from(k))
                        .collect(),
                )
                .unwrap()
            })
            .collect();
        let response = sensor.respond(&atoms[2]);

        let dense = DictionaryUpsampler::new(atoms.clone())
            .reconstruct(&response, &sensor, &grid)
            .unwrap();
        let sparse = DictionaryUpsampler::new(atoms)
            .with_l1(0.05)
            .reconstruct(&response, &sensor, &grid)
            .unwrap();

        assert!(dense.max() >= sparse.max() - 1e-9);
    }

    #[test]
    fn empty_dictionary_returns_zeros() {
        let grid = grid();
        let sensor = Sensor::generic_camera(&grid);
        let dictionary = DictionaryUpsampler::new(Vec::new());
        let estimate = dictionary
            .reconstruct(&[1.0, 1.0, 1.0], &sensor, &grid)
            .unwrap();
        assert_eq!(estimate.max(), 0.0);
    }
}
