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
//! prior is the target, but it needs a baked lookup table to be usable per
//! pixel, and that is a separate task.

use kallotype_spectral::{DictionaryUpsampler, PolynomialUpsampler, Sensor, Spectrum, Upsampler};

use crate::model::{ExposureModel, inverse3, tables};

/// First wavelength of the internal grid, in nanometres.
pub const GRID_START_NM: f64 = 380.0;
/// Wavelength step of the internal grid.
pub const GRID_STEP_NM: f64 = 5.0;
/// Number of samples on the internal grid.
pub const GRID_LEN: usize = 71;

/// Which sensor the RGB triple is assumed to have come from.
///
/// This is the assumption the whole spectral path is conditional on, so it is a
/// named, recorded choice rather than a constant buried in a constructor. The
/// name reaches `SpectralContext::identity`, which reaches every baked table, so
/// a table cannot be loaded against a different camera by accident.
#[derive(Debug, Clone, Default)]
pub enum CameraProfile {
    /// The linear sRGB primaries: the triple is an sRGB colour, which is what
    /// the program is actually handed. The default, because it is the only
    /// option that is exactly right for the input.
    #[default]
    Srgb,
    /// Three broad Gaussians: the stand-in from before any measured camera
    /// existed. Kept because it is the assumption the early benchmarks used.
    Generic,
    /// The CIE 1931 2 degree observer, for input that is already XYZ.
    Observer,
    /// A measured spectral sensitivity, for example an import of the camSPEC
    /// database.
    Measured(Sensor),
}

impl CameraProfile {
    /// The sensor's name, for the render report and for baked-table identity.
    #[must_use]
    pub fn name(&self) -> &str {
        match self {
            Self::Srgb => "srgb-primaries",
            Self::Generic => "generic-camera",
            Self::Observer => "cie1931-approx",
            Self::Measured(sensor) => sensor.name(),
        }
    }

    /// Build the sensor on `grid`.
    #[must_use]
    pub fn sensor(&self, grid: &kallotype_spectral::Spectrum) -> Sensor {
        match self {
            Self::Srgb => Sensor::srgb(grid),
            Self::Generic => Sensor::generic_camera(grid),
            Self::Observer => Sensor::cie1931(grid),
            Self::Measured(sensor) => sensor.resampled(grid),
        }
    }
}

/// Everything the spectral exposure needs, built once per render.
#[derive(Debug, Clone)]
pub struct SpectralContext {
    grid: Spectrum,
    camera: Sensor,
    film: Sensor,
    upsampler: PolynomialUpsampler,
    /// When present, the dictionary is tried first and the polynomial is the
    /// fallback.
    dictionary: Option<DictionaryUpsampler>,
    threshold: f64,
    /// Film response to a correctly exposed 18 % grey, per layer. Dividing by it
    /// keeps the spectral path anchored to the same grey as the scalar path, so
    /// that turning spectra on changes colour separation, not overall exposure.
    reference: [f64; 3],
    /// The cyan dye's second emulsion, resampled onto the model grid — ADR 0017.
    ///
    /// It is a fourth integral rather than a fourth number in `film`: the
    /// sensitivity is a table, and the layer it belongs to shares its dye with
    /// the blue-sensitive one instead of owning a channel.
    extra: Option<[f64; GRID_LEN]>,
}

impl Default for SpectralContext {
    fn default() -> Self {
        Self::new()
    }
}

impl SpectralContext {
    /// Build the context on the internal grid, with the default camera profile
    /// and the default film's layers.
    ///
    /// The film's layers are measured from the manufacturer's data sheet; the
    /// camera is [`CameraProfile::default`], the input's own definition. Both
    /// are ordered R, G, B, and getting that order wrong is invisible until a
    /// red patch comes out blue.
    ///
    /// This is the context for whichever stock [`crate::RenderParams::default`]
    /// uses. A render of any other film wants [`Self::for_stock`], or the
    /// exposure is computed with VISION3's spectral response and only the curve
    /// changes.
    ///
    /// # Panics
    ///
    /// Cannot panic: the grid is a compile-time constant with a valid step.
    #[must_use]
    pub fn new() -> Self {
        Self::for_layers("vision3_500t", &kallotype_spectral::layers::CHANNELS)
    }

    /// The context for a particular film stock: its own layer sensitivities.
    ///
    /// This is the difference between "a film with a different curve" and "a
    /// different film": which wavelengths each layer records decides how the
    /// scene separates into dyes, and no curve can stand in for it.
    #[must_use]
    pub fn for_stock(stock: &crate::emulsion::FilmStock) -> Self {
        let mut context = Self::for_layers(stock.id, stock.layers);
        // The three layers are divided by their joint peak when the sensor is
        // built, so a fourth table has to be divided by the same number or it
        // would be on a scale of its own and every exposure it reported would
        // be off by that factor. Normalising it on its *own* peak would be the
        // other mistake: it would assert that the cyan-sensitive emulsion is
        // exactly as fast as the blue-sensitive one.
        let peak = stock
            .layers
            .iter()
            .flat_map(|table| table.iter())
            .fold(0.0_f64, |a, &b| a.max(b));
        context.extra = stock
            .extra_cyan
            .and_then(|emulsion| sensitivity_table(&context.grid, emulsion.sensitivity, peak));
        context
    }

    /// # Panics
    ///
    /// Cannot panic: the grid is a compile-time constant with a valid step.
    #[must_use]
    fn for_layers(name: &str, layers: &[[f64; GRID_LEN]; 3]) -> Self {
        let grid = Spectrum::uniform(GRID_START_NM, GRID_STEP_NM, GRID_LEN)
            .expect("the internal grid is a valid constant");
        let camera = CameraProfile::default().sensor(&grid);
        let film = Sensor::film_layers_from(&grid, name, layers);
        let upsampler = PolynomialUpsampler;

        let mut context = Self {
            grid,
            camera,
            film,
            upsampler,
            dictionary: None,
            threshold: 0.02,
            reference: [1.0; 3],
            extra: None,
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

    /// Replace the camera assumption.
    ///
    /// The grey anchor is recomputed, because it is the film's response to the
    /// spectrum this camera reconstructs for mid grey. Changing the camera
    /// without that would silently re-balance every print.
    #[must_use]
    pub fn with_camera(mut self, camera: CameraProfile) -> Self {
        self.camera = camera.sensor(&self.grid);
        self.refresh_reference();
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

    /// A stable description of the model this context implements.
    ///
    /// Recorded in baked tables so that loading a table baked for a different
    /// camera or film fails loudly instead of silently producing wrong colour.
    #[must_use]
    pub fn identity(&self) -> String {
        format!(
            "camera={};film={};grid={}:{}:{}",
            self.camera.name(),
            self.film.name(),
            self.grid.start_nm(),
            self.grid.step_nm(),
            self.grid.len()
        )
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

    /// The film's three layer sensitivities.
    #[must_use]
    pub fn film(&self) -> &Sensor {
        &self.film
    }

    /// The film's response to a reconstructed 18 % grey, per layer.
    ///
    /// The anchor [`Self::expose`] divides by: an integrator that wants the
    /// same anchor needs this number rather than a second reconstruction.
    #[must_use]
    pub fn reference(&self) -> [f64; 3] {
        self.reference
    }

    /// The constants this context integrates with, flattened for another backend.
    ///
    /// `None` when a dictionary prior is active, or when a table is not on the
    /// model's grid. Both mean the closed form below is not what this context
    /// computes, and a backend that rendered anyway would be rendering a
    /// different model without saying so.
    #[must_use]
    pub fn model(&self) -> Option<ExposureModel> {
        if self.has_dictionary() {
            return None;
        }
        let basis = PolynomialUpsampler::basis(&self.grid);
        let system = self.upsampler.system(&self.camera, &self.grid).ok()?;
        Some(ExposureModel {
            // The CPU's own fallback for a singular system is zero
            // coefficients, which is exactly the zero matrix for every input.
            reconstruct: inverse3(system).unwrap_or([[0.0; 3]; 3]),
            basis: tables(&basis)?,
            film: tables(self.film.channels())?,
            reference: self.reference,
        })
    }

    /// Per-layer log10 exposure for a linear-light pixel.
    ///
    /// Returns `None` if the reconstruction fails, which can only happen on a
    /// grid mismatch that [`Self::new`] rules out.
    #[must_use]
    pub fn expose(&self, linear: [f64; 3]) -> Option<[f64; 3]> {
        self.expose_with_extra(linear).map(|(layers, _)| layers)
    }

    /// The same exposure, plus the fourth layer when the film has one.
    ///
    /// One reconstruction feeds all four integrals: the second cyan emulsion
    /// sits in the same stack and sees the same light, so rebuilding the
    /// spectrum for it would be the same arithmetic twice.
    ///
    /// The fourth layer is normalised on the **blue** layer's grey response,
    /// not on its own. The data sheet plots every emulsion on one log H axis,
    /// so the distance between the blue-sensitive curve and the cyan-sensitive
    /// one is a speed difference; anchoring each on its own grey would divide
    /// that difference out and make the fourth layer a copy of the third.
    #[must_use]
    pub fn expose_with_extra(&self, linear: [f64; 3]) -> Option<([f64; 3], Option<f64>)> {
        let spectrum = self.reconstruct(linear)?;
        let radiance = spectrum.values();
        let response = self.film.respond(&spectrum);
        let layers = std::array::from_fn(|channel| {
            let normalised = response[channel] * 0.18 / self.reference[channel].max(1e-12);
            normalised.max(1e-10).log10()
        });
        let extra = self.extra.map(|sensitivity| {
            let total = sensitivity
                .iter()
                .zip(radiance)
                .map(|(sensitivity, radiance)| sensitivity * radiance)
                .sum::<f64>()
                * self.grid.step_nm();
            let normalised = total * 0.18 / self.reference[2].max(1e-12);
            normalised.max(1e-10).log10()
        });
        Some((layers, extra))
    }
}

/// A sensitivity table on its own grid, resampled onto the model's.
///
/// `peak` is the divisor that puts it on the same relative scale as the film's
/// three layers — see [`SpectralContext::for_stock`].
///
/// `None` for an empty table, which is an emulsion that records nothing — a
/// layer with no sensitivity would develop only base, and pretending it does is
/// worse than saying the stock has no fourth emulsion.
fn sensitivity_table(grid: &Spectrum, sensitivity: &[f32], peak: f64) -> Option<[f64; GRID_LEN]> {
    if sensitivity.is_empty() || peak <= 0.0 {
        return None;
    }
    let mut table = Spectrum::uniform(
        crate::dye::SENSITIVITY_START_NM,
        crate::dye::SENSITIVITY_STEP_NM,
        sensitivity.len(),
    )
    .ok()?;
    for (slot, value) in table.values_mut().iter_mut().zip(sensitivity) {
        *slot = f64::from(*value) / peak;
    }
    crate::model::table(&table.resampled(grid))
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

    /// The default camera is the input's own definition, so the reconstruction
    /// has to give the colour back exactly — as long as the prior can hold it.
    #[test]
    fn the_default_camera_gives_back_the_colour_it_was_handed() {
        let context = SpectralContext::new();
        for linear in [
            [0.18, 0.18, 0.18],
            [0.9, 0.1, 0.1],
            [0.1, 0.1, 0.9],
            [0.4, 0.3, 0.2],
        ] {
            let spectrum = context.reconstruct(linear).expect("polynomial solves");
            let back = context.camera().respond(&spectrum);
            for channel in 0..3 {
                assert!(
                    (back[channel] - linear[channel]).abs() < 1e-6,
                    "{linear:?} came back as {back:?}"
                );
            }
        }
    }

    /// Where the smooth prior cannot hold the colour, the clamp is what gives it
    /// away: the quadratic goes negative and the reflectance floor lifts the
    /// response. This is the polynomial's floor, not the camera's — the solve
    /// before the clamp is exact — and it is why the dictionary exists.
    #[test]
    fn a_saturated_green_exceeds_what_the_smooth_prior_can_hold() {
        let context = SpectralContext::new();
        let linear = [0.1, 0.9, 0.1];
        let spectrum = context.reconstruct(linear).expect("polynomial solves");
        let back = context.camera().respond(&spectrum);
        assert!(spectrum.min() >= 0.0, "reflectance went negative");
        assert!(
            back[0] > 0.2,
            "expected the clamp to lift red above 0.2, got {back:?}"
        );
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
