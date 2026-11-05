//! How wrong is a reconstruction? Three answers, from cheap to relevant.
//!
//! - [`rmse`] — how far apart the curves are, in reflectance units.
//! - [`spectral_angle_deg`] — the shape error, ignoring overall brightness.
//! - [`relative_response_error`] — what actually matters: how much the error
//!   moves the *film's* three layers. A reconstruction can be ugly and still
//!   harmless, or pretty and badly wrong downstream.

use crate::sensor::Sensor;
use crate::spectrum::{SpectralError, Spectrum};

/// Root-mean-square difference in reflectance units.
///
/// # Errors
///
/// Returns an error if the spectra are on different grids.
pub fn rmse(truth: &Spectrum, estimate: &Spectrum) -> Result<f64, SpectralError> {
    if !truth.shares_grid(estimate) {
        return Err(SpectralError::GridMismatch {
            left: format!("{}-{} nm", truth.start_nm(), truth.end_nm()),
            right: format!("{}-{} nm", estimate.start_nm(), estimate.end_nm()),
        });
    }
    let sum: f64 = truth
        .values()
        .iter()
        .zip(estimate.values())
        .map(|(a, b)| (a - b) * (a - b))
        .sum();
    Ok((sum / truth.len() as f64).sqrt())
}

/// Spectral angle in degrees; 0 means identical shape.
///
/// # Errors
///
/// Returns an error if the spectra are on different grids.
pub fn spectral_angle_deg(truth: &Spectrum, estimate: &Spectrum) -> Result<f64, SpectralError> {
    // The wavelength step cancels between numerator and denominator, so the
    // discrete inner product is used directly. Using `dot` here would scale the
    // cosine by the step and clamp every angle to zero.
    let dot: f64 = truth
        .values()
        .iter()
        .zip(estimate.values())
        .map(|(a, b)| a * b)
        .sum();
    if !truth.shares_grid(estimate) {
        return Err(SpectralError::GridMismatch {
            left: format!("{}-{} nm", truth.start_nm(), truth.end_nm()),
            right: format!("{}-{} nm", estimate.start_nm(), estimate.end_nm()),
        });
    }
    let norm = |spectrum: &Spectrum| -> f64 {
        spectrum
            .values()
            .iter()
            .map(|value| value * value)
            .sum::<f64>()
            .sqrt()
    };
    let denominator = norm(truth) * norm(estimate);
    if denominator < 1e-12 {
        return Ok(0.0);
    }
    let cosine = (dot / denominator).clamp(-1.0, 1.0);
    Ok(cosine.acos().to_degrees())
}

/// Per-channel relative error in the response of `sensor`.
///
/// This is the downstream metric: it answers "how much does this
/// reconstruction error change what the film sees", in percent.
#[must_use]
pub fn relative_response_error(sensor: &Sensor, truth: &Spectrum, estimate: &Spectrum) -> [f64; 3] {
    let reference = sensor.respond(truth);
    let measured = sensor.respond(estimate);
    std::array::from_fn(|index| {
        let base = reference[index].abs().max(1e-9);
        (measured[index] - reference[index]) / base * 100.0
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn grid() -> Spectrum {
        Spectrum::uniform(380.0, 10.0, 36).unwrap()
    }

    #[test]
    fn identical_spectra_have_no_error() {
        let grid = grid();
        let value = Spectrum::filled(grid.clone(), 0.5);
        assert!(rmse(&value, &value).unwrap() < 1e-12);
        assert!(spectral_angle_deg(&value, &value).unwrap() < 1e-9);
    }

    #[test]
    fn a_scaled_copy_has_angle_zero_but_rmse_nonzero() {
        let grid = grid();
        let value = Spectrum::filled(grid, 0.5);
        let scaled = value.scaled(2.0);
        assert!(spectral_angle_deg(&value, &scaled).unwrap() < 1e-9);
        assert!(rmse(&value, &scaled).unwrap() > 0.1);
    }
}
