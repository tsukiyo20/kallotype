//! A sampled spectrum on a uniform wavelength grid.

use std::fmt;

/// Something went wrong building or combining spectra.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SpectralError {
    /// A grid needs at least one sample.
    Empty,
    /// The wavelength step must be positive.
    NonPositiveStep(std::string::String),
    /// Two spectra were combined on different grids.
    GridMismatch {
        /// Step of the left operand.
        left: std::string::String,
        /// Step of the right operand.
        right: std::string::String,
    },
    /// A value was not finite.
    NotFinite(usize),
}

impl fmt::Display for SpectralError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Empty => write!(f, "a spectrum needs at least one sample"),
            Self::NonPositiveStep(step) => {
                write!(f, "wavelength step must be positive, got {step}")
            }
            Self::GridMismatch { left, right } => {
                write!(f, "spectra are on different grids: {left} vs {right}")
            }
            Self::NotFinite(index) => write!(f, "sample {index} is not finite"),
        }
    }
}

impl std::error::Error for SpectralError {}

/// A spectrum sampled at a fixed wavelength step.
#[derive(Debug, Clone, PartialEq)]
pub struct Spectrum {
    start_nm: f64,
    step_nm: f64,
    values: Vec<f64>,
}

impl Spectrum {
    /// Build a spectrum from an explicit grid and values.
    pub fn new(start_nm: f64, step_nm: f64, values: Vec<f64>) -> Result<Self, SpectralError> {
        if values.is_empty() {
            return Err(SpectralError::Empty);
        }
        if !(step_nm.is_finite() && step_nm > 0.0) {
            return Err(SpectralError::NonPositiveStep(step_nm.to_string()));
        }
        if !start_nm.is_finite() {
            return Err(SpectralError::NonPositiveStep(start_nm.to_string()));
        }
        if let Some(index) = values.iter().position(|value| !value.is_finite()) {
            return Err(SpectralError::NotFinite(index));
        }
        Ok(Self {
            start_nm,
            step_nm,
            values,
        })
    }

    /// A uniform grid of `len` zero-valued samples.
    pub fn uniform(start_nm: f64, step_nm: f64, len: usize) -> Result<Self, SpectralError> {
        Self::new(start_nm, step_nm, vec![0.0; len])
    }

    /// A copy of `template`'s grid filled with a constant.
    #[must_use]
    pub fn filled(template: Self, value: f64) -> Self {
        let mut out = template;
        out.values.fill(value);
        out
    }

    /// Number of samples.
    #[must_use]
    pub fn len(&self) -> usize {
        self.values.len()
    }

    /// Whether the spectrum has no samples. Cannot happen in practice: the
    /// constructors reject it.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.values.is_empty()
    }

    /// Wavelength of the first sample.
    #[must_use]
    pub fn start_nm(&self) -> f64 {
        self.start_nm
    }

    /// Wavelength step.
    #[must_use]
    pub fn step_nm(&self) -> f64 {
        self.step_nm
    }

    /// Wavelength of the last sample.
    #[must_use]
    pub fn end_nm(&self) -> f64 {
        self.start_nm + self.step_nm * (self.values.len() as f64 - 1.0)
    }

    /// The samples.
    #[must_use]
    pub fn values(&self) -> &[f64] {
        &self.values
    }

    /// Mutable access to the samples.
    pub fn values_mut(&mut self) -> &mut [f64] {
        &mut self.values
    }

    /// Wavelength of sample `index`, if it exists.
    #[must_use]
    pub fn wavelength(&self, index: usize) -> Option<f64> {
        (index < self.values.len()).then_some(self.start_nm + self.step_nm * index as f64)
    }

    /// Linear interpolation, clamped at both ends.
    #[must_use]
    pub fn interpolate(&self, wavelength_nm: f64) -> f64 {
        let position = (wavelength_nm - self.start_nm) / self.step_nm;
        if position <= 0.0 {
            return self.values[0];
        }
        let last = self.values.len() - 1;
        if position >= last as f64 {
            return self.values[last];
        }
        let low = position.floor() as usize;
        let fraction = position - low as f64;
        self.values[low] * (1.0 - fraction) + self.values[low + 1] * fraction
    }

    /// Whether two spectra share a grid.
    #[must_use]
    pub fn shares_grid(&self, other: &Self) -> bool {
        self.values.len() == other.values.len()
            && (self.start_nm - other.start_nm).abs() < 1e-9
            && (self.step_nm - other.step_nm).abs() < 1e-9
    }

    fn check_grid(&self, other: &Self) -> Result<(), SpectralError> {
        if self.shares_grid(other) {
            Ok(())
        } else {
            Err(SpectralError::GridMismatch {
                left: format!("{}-{} nm", self.start_nm, self.end_nm()),
                right: format!("{}-{} nm", other.start_nm, other.end_nm()),
            })
        }
    }

    /// Integral of `self * other` over wavelength, by the rectangle rule.
    pub fn dot(&self, other: &Self) -> Result<f64, SpectralError> {
        self.check_grid(other)?;
        let sum: f64 = self
            .values
            .iter()
            .zip(&other.values)
            .map(|(a, b)| a * b)
            .sum();
        Ok(sum * self.step_nm)
    }

    /// Multiply every sample by `factor`.
    #[must_use]
    pub fn scaled(&self, factor: f64) -> Self {
        let mut out = self.clone();
        for value in &mut out.values {
            *value *= factor;
        }
        out
    }

    /// Resample onto `grid` by linear interpolation.
    #[must_use]
    pub fn resampled(&self, grid: &Self) -> Self {
        let values = (0..grid.len())
            .map(|index| self.interpolate(grid.start_nm + grid.step_nm * index as f64))
            .collect();
        Self {
            start_nm: grid.start_nm,
            step_nm: grid.step_nm,
            values,
        }
    }

    /// Largest sample.
    #[must_use]
    pub fn max(&self) -> f64 {
        self.values
            .iter()
            .copied()
            .fold(f64::NEG_INFINITY, f64::max)
    }

    /// Smallest sample.
    #[must_use]
    pub fn min(&self) -> f64 {
        self.values.iter().copied().fold(f64::INFINITY, f64::min)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ramp() -> Spectrum {
        Spectrum::new(380.0, 10.0, (0..5).map(f64::from).collect()).unwrap()
    }

    #[test]
    fn interpolation_is_linear_and_clamped() {
        let s = ramp();
        assert!((s.interpolate(385.0) - 0.5).abs() < 1e-12);
        assert!((s.interpolate(300.0) - 0.0).abs() < 1e-12);
        assert!((s.interpolate(900.0) - 4.0).abs() < 1e-12);
    }

    #[test]
    fn dot_uses_the_wavelength_step() {
        let s = Spectrum::new(380.0, 10.0, vec![1.0; 3]).unwrap();
        // Three samples of 1.0 x 1.0, each 10 nm wide.
        assert!((s.dot(&s).unwrap() - 30.0).abs() < 1e-12);
    }

    #[test]
    fn mismatched_grids_are_rejected() {
        let a = Spectrum::new(380.0, 10.0, vec![1.0; 3]).unwrap();
        let b = Spectrum::new(380.0, 5.0, vec![1.0; 3]).unwrap();
        assert!(a.dot(&b).is_err());
    }

    #[test]
    fn empty_and_non_finite_are_rejected() {
        assert!(Spectrum::new(380.0, 10.0, vec![]).is_err());
        assert!(Spectrum::new(380.0, 0.0, vec![1.0]).is_err());
        assert!(Spectrum::new(380.0, 10.0, vec![f64::NAN]).is_err());
    }
}
