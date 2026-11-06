//! Spectral exposure: linear RGB → spectrum → film layer responses.
//!
//! Phase 0 exposed the negative by taking each channel's log exposure directly.
//! That is a scalar approximation: it assumes the film's three layers see the
//! same three numbers the camera does. They do not.
//!
//! This module inserts the missing step. The camera triple is reconstructed into
//! a spectrum, and that spectrum is integrated against the film's layer
//! sensitivities. The result is still three log exposures, but they come from a
//! physical overlap rather than from an identity.
//!
//! The reconstruction used here is the **fast** member of the family: the
//! polynomial prior, which is a closed-form 3×3 solve per pixel. The dictionary
//! prior measured in `docs/0002-rgb-to-spectrum.md` is the target, but it needs a
//! baked lookup table to be usable per pixel, and that is a separate task.

use kallotype_spectral::{DictionaryUpsampler, PolynomialUpsampler, Sensor, Spectrum, Upsampler};

/// First wavelength of the internal grid, in nanometres.
pub const GRID_START_NM: f64 = 380.0;
/// Wavelength step of the internal grid.
pub const GRID_STEP_NM: f64 = 5.0;
/// Number of samples on the internal grid.
pub const GRID_LEN: usize = 71;

/// Everything the spectral exposure needs, built once per render.
#[derive(Debug, Clone)]
pub struct SpectralContext {
    grid: Spectrum,
    camera: Sensor,
    film: Sensor,
    upsampler: PolynomialUpsampler,
    /// When present, the dictionary is tried first and the polynomial is the
    /// fallback — the hybrid measured in `docs/0002-rgb-to-spectrum.md`.
    dictionary: Option<DictionaryUpsampler>,
    threshold: f64,
    /// Film response to a correctly exposed 18 % grey, per layer. Dividing by it
    /// keeps the spectral path anchored to the same grey as the scalar path, so
    /// that turning spectra on changes colour separation, not overall exposure.
    reference: [f64; 3],
}

impl Default for SpectralContext {
    fn default() -> Self {
        Self::new()
    }
}

impl SpectralContext {
    /// Build the context on the internal grid.
    ///
    /// Both sensors are **test instruments** from `kallotype-spectral`: three
    /// broad Gaussian channels as the camera and three Gaussian layers as the
    /// film, both ordered R, G, B. They are placeholders with recorded
    /// provenance — see `docs/0003-camera-assumption.md` for what that costs.
    ///
    /// # Panics
    ///
    /// Cannot panic: the grid is a compile-time constant with a valid step.
    #[must_use]
    pub fn new() -> Self {
        let grid = Spectrum::uniform(GRID_START_NM, GRID_STEP_NM, GRID_LEN)
            .expect("the internal grid is a valid constant");
        let camera = Sensor::generic_camera(&grid);
        let film = Sensor::film_layers(&grid);
        let upsampler = PolynomialUpsampler;

        let mut context = Self {
            grid,
            camera,
            film,
            upsampler,
            dictionary: None,
            threshold: 0.02,
            reference: [1.0; 3],
        };
        context.refresh_reference();
        context
    }

    /// Recompute the grey anchor with whatever reconstruction is now active.
    ///
    /// This matters: the anchor must be measured through the same path that
    /// renders, or enabling the dictionary would silently re-balance every print.
    fn refresh_reference(&mut self) {
        let grey = self
            .reconstruct([0.18; 3])
            .unwrap_or_else(|| Spectrum::filled(self.grid.clone(), 0.0));
        self.reference = self.film.respond(&grey);
    }

    /// Use a dictionary prior, with the polynomial as the fallback.
    ///
    /// Atoms are resampled onto the internal grid, so callers can pass spectra
    /// measured on any uniform grid.
    #[must_use]
    pub fn with_atoms(mut self, atoms: &[Spectrum]) -> Self {
        let resampled: Vec<Spectrum> = atoms
            .iter()
            .map(|atom| atom.resampled(&self.grid))
            .collect();
        if !resampled.is_empty() {
            self.dictionary = Some(DictionaryUpsampler::new(resampled));
            self.refresh_reference();
        }
        self
    }

    /// Relative camera-response residual above which the hybrid falls back.
    #[must_use]
    pub fn with_threshold(mut self, threshold: f64) -> Self {
        self.threshold = threshold.max(0.0);
        self
    }

    /// Whether a dictionary prior is active.
    #[must_use]
    pub fn has_dictionary(&self) -> bool {
        self.dictionary.is_some()
    }

    /// The wavelength grid.
    #[must_use]
    pub fn grid(&self) -> &Spectrum {
        &self.grid
    }

    /// The camera assumption this context was built with.
    #[must_use]
    pub fn camera(&self) -> &Sensor {
        &self.camera
    }

    /// Per-layer log10 exposure for a linear-light pixel.
    ///
    /// Returns `None` if the reconstruction fails, which can only happen on a
    /// grid mismatch that [`Self::new`] rules out.
    #[must_use]
    pub fn expose(&self, linear: [f64; 3]) -> Option<[f64; 3]> {
        let spectrum = self.reconstruct(linear)?;
        let response = self.film.respond(&spectrum);
        Some(std::array::from_fn(|channel| {
            let normalised = response[channel] * 0.18 / self.reference[channel].max(1e-12);
            normalised.max(1e-10).log10()
        }))
    }
}

impl SpectralContext {
    /// Pick a reconstruction: the dictionary if it can explain the measurement,
    /// the polynomial otherwise.
    fn reconstruct(&self, linear: [f64; 3]) -> Option<Spectrum> {
        if let Some(dictionary) = &self.dictionary {
            let candidate = dictionary
                .reconstruct(&linear, &self.camera, &self.grid)
                .ok()?;
            let measured = self.camera.respond(&candidate);
            let residual: f64 = (0..3)
                .map(|index| (measured[index] - linear[index]).powi(2))
                .sum::<f64>()
                .sqrt();
            let scale: f64 = (0..3)
                .map(|index| linear[index].powi(2))
                .sum::<f64>()
                .sqrt()
                .max(1e-9);
            if residual / scale <= self.threshold {
                return Some(candidate);
            }
        }
        self.upsampler
            .reconstruct(&linear, &self.camera, &self.grid)
            .ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mid_grey_stays_at_mid_grey() {
        let context = SpectralContext::new();
        let log_e = context.expose([0.18, 0.18, 0.18]).unwrap();
        let expected = 0.18_f64.log10();
        for channel in log_e {
            assert!((channel - expected).abs() < 1e-6, "{channel} vs {expected}");
        }
    }

    #[test]
    fn a_saturated_colour_separates_the_layers() {
        let context = SpectralContext::new();
        let log_e = context.expose([0.9, 0.1, 0.1]).unwrap();
        // The red layer must see more than the blue one.
        assert!(log_e[0] > log_e[2], "{log_e:?}");
        // The magnitude is a property of the placeholder film sensor, so only
        // the direction and the presence of separation are asserted here.
        assert!((log_e[0] - log_e[2]) > 0.05, "no separation: {log_e:?}");
    }

    #[test]
    fn a_dictionary_is_used_when_it_covers_the_colour() {
        let context = SpectralContext::new();
        let atoms: Vec<Spectrum> = [0.18_f64, 0.4, 0.05]
            .iter()
            .map(|level| {
                context
                    .upsampler
                    .reconstruct(&[*level; 3], context.camera(), context.grid())
                    .unwrap()
            })
            .collect();
        let with_dictionary = context.with_atoms(&atoms);
        assert!(with_dictionary.has_dictionary());

        let neutral = with_dictionary.expose([0.18; 3]).unwrap();
        assert!((neutral[0] - 0.18_f64.log10()).abs() < 1e-6);
    }

    #[test]
    fn exposure_is_monotonic() {
        let context = SpectralContext::new();
        let mut previous = f64::NEG_INFINITY;
        for step in 0..40 {
            let value = 0.001 * 1.2_f64.powi(step);
            let log_e = context.expose([value; 3]).unwrap()[1];
            assert!(log_e > previous, "not monotonic at {value}");
            previous = log_e;
        }
    }
}
