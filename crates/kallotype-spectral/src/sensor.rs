//! A three-channel sensor: the thing that turns a spectrum into RGB.
//!
//! The sensor is the pivot of the whole metamerism problem. Two different
//! spectra that produce the same three numbers under *this* matrix are
//! indistinguishable to the camera, and any reconstruction has to pick one of
//! them. Which one it picks is the model.

use crate::spectrum::{SpectralError, Spectrum};

/// Three spectral response curves sampled on a common grid.
#[derive(Debug, Clone)]
pub struct Sensor {
    name: String,
    channels: [Spectrum; 3],
}

impl Sensor {
    /// Build a sensor from three response curves.
    ///
    /// # Errors
    ///
    /// Returns [`SpectralError::GridMismatch`] if the channels disagree on the
    /// grid.
    pub fn new(name: impl Into<String>, channels: [Spectrum; 3]) -> Result<Self, SpectralError> {
        for channel in &channels[1..] {
            if !channels[0].shares_grid(channel) {
                return Err(SpectralError::GridMismatch {
                    left: format!("{}-{} nm", channels[0].start_nm(), channels[0].end_nm()),
                    right: format!("{}-{} nm", channel.start_nm(), channel.end_nm()),
                });
            }
        }
        Ok(Self {
            name: name.into(),
            channels,
        })
    }

    /// A human-readable name, reported by the benchmark.
    #[must_use]
    pub fn name(&self) -> &str {
        &self.name
    }

    /// The three response curves.
    #[must_use]
    pub fn channels(&self) -> &[Spectrum; 3] {
        &self.channels
    }

    /// Measure a spectrum.
    ///
    /// # Panics
    ///
    /// Panics only if the spectrum is on a different grid, which
    /// [`Sensor::new`] already rules out.
    #[must_use]
    pub fn respond(&self, spectrum: &Spectrum) -> [f64; 3] {
        self.channels
            .each_ref()
            .map(|channel| channel.dot(spectrum).unwrap_or(0.0))
    }

    /// A generic camera: three broad overlapping curves.
    ///
    /// This is a **test instrument**, not a measurement. It exists so the
    /// benchmark can run before any real spectral sensitivities have been
    /// collected.
    #[must_use]
    pub fn generic_camera(grid: &Spectrum) -> Self {
        Self::from_gaussians(
            grid,
            "generic-camera",
            [(450.0, 38.0), (545.0, 42.0), (620.0, 48.0)],
        )
    }

    /// A stand-in for a film's three layer sensitivities.
    ///
    /// Sits where the benchmark wants it: shifted relative to the camera, which
    /// is exactly why a metameric error in the reconstruction shows up as an
    /// error in dye density.
    #[must_use]
    pub fn film_layers(grid: &Spectrum) -> Self {
        Self::from_gaussians(
            grid,
            "film-layers",
            [(445.0, 30.0), (550.0, 35.0), (650.0, 50.0)],
        )
    }

    fn from_gaussians(grid: &Spectrum, name: &str, peaks: [(f64, f64); 3]) -> Self {
        let channels: [Spectrum; 3] = peaks.map(|(mu, sigma)| {
            let mut channel = Spectrum::filled(grid.clone(), 0.0);
            for (index, value) in channel.values_mut().iter_mut().enumerate() {
                let wavelength = grid.start_nm() + grid.step_nm() * index as f64;
                let z = (wavelength - mu) / sigma;
                *value = (-0.5 * z * z).exp();
            }
            // Unit integral, so a perfectly white spectrum responds with 1.0.
            let area: f64 = channel.values().iter().sum::<f64>() * channel.step_nm();
            if area > 0.0 {
                for value in channel.values_mut() {
                    *value /= area;
                }
            }
            channel
        });
        Self {
            name: name.to_owned(),
            channels,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_flat_spectrum_responds_with_unit_area_mass() {
        let grid = Spectrum::uniform(380.0, 10.0, 36).unwrap();
        let flat = Spectrum::filled(grid.clone(), 1.0);
        let sensor = Sensor::generic_camera(&grid);
        for response in sensor.respond(&flat) {
            assert!((response - 1.0).abs() < 1e-9, "response {response}");
        }
    }

    #[test]
    fn channels_must_share_a_grid() {
        let a = Spectrum::uniform(380.0, 10.0, 36).unwrap();
        let b = Spectrum::uniform(380.0, 5.0, 71).unwrap();
        assert!(Sensor::new("bad", [a.clone(), b, a]).is_err());
    }
}
