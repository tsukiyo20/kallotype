//! A three-channel sensor: the thing that turns a spectrum into RGB.
//!
//! The sensor is the pivot of the whole metamerism problem. Two different
//! spectra that produce the same three numbers under *this* matrix are
//! indistinguishable to the camera, and any reconstruction has to pick one of
//! them. Which one it picks is the model.

use crate::layers;
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

    /// Each channel divided by its own integral.
    ///
    /// This is a statement about the *input encoding*, not about the sensor: it
    /// makes a flat spectrum respond equally in all three channels, which is
    /// what a white-balanced triple means. A raw camera response does not, and
    /// the database's own channel levels are consequently not used when a
    /// measured sensitivity is loaded for white-balanced input.
    #[must_use]
    pub fn area_normalized(&self) -> Self {
        let channels: [Spectrum; 3] = self.channels.each_ref().map(|channel| {
            let area: f64 = channel.values().iter().sum::<f64>() * channel.step_nm();
            if area.abs() > 1e-12 {
                channel.scaled(1.0 / area)
            } else {
                channel.clone()
            }
        });
        Self {
            name: self.name.clone(),
            channels,
        }
    }

    /// The same response curves sampled on another grid.
    ///
    /// Channels keep their shape and their relative scale; values outside the
    /// original span are clamped, which is what [`Spectrum::resampled`] does.
    #[must_use]
    pub fn resampled(&self, grid: &Spectrum) -> Self {
        if self.channels[0].shares_grid(grid) {
            return self.clone();
        }
        Self {
            name: self.name.clone(),
            channels: self
                .channels
                .each_ref()
                .map(|channel| channel.resampled(grid)),
        }
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

    /// A generic camera: three broad overlapping curves, in R, G, B order.
    ///
    /// This is a **test instrument**, not a measurement. It exists so the
    /// benchmark can run before any real spectral sensitivities have been
    /// collected.
    ///
    /// The order is part of the contract, not a detail. Channels are indexed
    /// the same way everywhere in this crate and in `kallotype-core`, so
    /// channel 0 has to be the one that sees red. This constructor used to list
    /// its peaks blue-first while [`Self::generic_camera_shifted`] listed them
    /// red-first; with a film whose layers were also blue-first, red in still
    /// came out red, so nothing noticed until the film's layers were replaced
    /// with measured ones. Two orderings that agree with each other and with
    /// nothing else are still two orderings.
    #[must_use]
    pub fn generic_camera(grid: &Spectrum) -> Self {
        Self::from_gaussians(
            grid,
            "generic-camera",
            [(620.0, 48.0), (545.0, 42.0), (450.0, 38.0)],
        )
    }

    /// The CIE 1931 2 degree observer, from the analytic fit of
    /// Wyman, Sloan and Shirley, *Simple Analytic Approximations to the CIE XYZ
    /// Color Matching Functions* (JCGT 2013).
    ///
    /// Still a test instrument — an approximation of the standard observer, not
    /// a measurement of any camera — but a far less arbitrary one than three
    /// Gaussians, and it is what an "unknown camera" defaults to in practice.
    /// Each channel is normalised to unit area, like [`Self::generic_camera`].
    #[must_use]
    pub fn cie1931(grid: &Spectrum) -> Self {
        let channels: [Spectrum; 3] = [0, 1, 2].map(|axis| {
            let mut channel = Spectrum::filled(grid.clone(), 0.0);
            for (index, value) in channel.values_mut().iter_mut().enumerate() {
                let wavelength = grid.start_nm() + grid.step_nm() * index as f64;
                *value = cie1931_xyz(wavelength)[axis].max(0.0);
            }
            let area: f64 = channel.values().iter().sum::<f64>() * channel.step_nm();
            if area > 0.0 {
                for value in channel.values_mut() {
                    *value /= area;
                }
            }
            channel
        });
        Self {
            name: "cie1931-approx".to_owned(),
            channels,
        }
    }

    /// The synthetic camera with all three peaks shifted by `shift_nm`.
    ///
    /// Not a model of any real device: a device for asking how much the answer
    /// depends on where the camera's channels sit. Real cameras differ from one
    /// another by more than this in peak position and much more in shape.
    #[must_use]
    pub fn generic_camera_shifted(grid: &Spectrum, shift_nm: f64) -> Self {
        Self::from_gaussians(
            grid,
            "generic-camera-shifted",
            [
                (620.0 + shift_nm, 48.0),
                (545.0 + shift_nm, 42.0),
                (450.0 + shift_nm, 38.0),
            ],
        )
    }

    /// The sRGB primaries, as three spectral weighting functions.
    ///
    /// An sRGB triple is defined by the inverse of the standard matrix, applied
    /// to CIE XYZ. Writing that out gives `R = ∫ S(λ) · r(λ) dλ` with
    ///
    /// ```text
    /// r =  3.2406 x̄ - 1.5372 ȳ - 0.4986 z̄
    /// g = -0.9689 x̄ + 1.8758 ȳ + 0.0415 z̄
    /// b =  0.0557 x̄ - 0.2040 ȳ + 1.0570 z̄
    /// ```
    ///
    /// This is the only basis that is *exactly* right for an sRGB input, and it
    /// is not a camera: the curves have negative lobes, which no sensor has, and
    /// they carry no noise, no IR-cut filter and no lens.
    ///
    /// Unlike the other constructors, the scale is not normalised. The matrix is
    /// the definition, and dividing the channels would silently redefine it.
    #[must_use]
    pub fn srgb(grid: &Spectrum) -> Self {
        const INVERSE: [[f64; 3]; 3] = [
            [3.2406, -1.5372, -0.4986],
            [-0.9689, 1.8758, 0.0415],
            [0.0557, -0.2040, 1.0570],
        ];
        let channels: [Spectrum; 3] = INVERSE.map(|row| {
            let mut channel = Spectrum::filled(grid.clone(), 0.0);
            for (index, value) in channel.values_mut().iter_mut().enumerate() {
                let wavelength = grid.start_nm() + grid.step_nm() * index as f64;
                let observer = cie1931_xyz(wavelength);
                *value = row[0] * observer[0] + row[1] * observer[1] + row[2] * observer[2];
            }
            channel
        });
        Self {
            name: "srgb-primaries".to_owned(),
            channels,
        }
    }

    /// The three layer sensitivities of KODAK VISION3 500T 5219/7219.
    ///
    /// Measured, not modelled: the curves come from the film's technical data
    /// sheet and live in [`crate::layers`]. They sit where the benchmark wants
    /// them — shifted relative to the camera — which is exactly why a metameric
    /// error in the reconstruction shows up as an error in dye density.
    ///
    /// The tables are sampled at 380–730 nm every 5 nm and resampled onto
    /// `grid`, so the caller's grid does not have to match.
    #[must_use]
    pub fn film_layers(grid: &Spectrum) -> Self {
        Self::film_layers_from(grid, "vision3-500t", &layers::CHANNELS)
    }

    /// A film stock's own layer sensitivities.
    ///
    /// The tables are divided by one constant — the largest sample across all
    /// three — rather than normalised per channel, so the layers' relative
    /// sensitivity survives. That is part of what a stock is: a film whose blue
    /// layer is twice as fast as another's renders differently, and normalising
    /// each channel would erase it.
    #[must_use]
    pub fn film_layers_from(grid: &Spectrum, name: &str, tables: &[[f64; layers::LEN]; 3]) -> Self {
        let native = Spectrum::uniform(layers::START_NM, layers::STEP_NM, layers::LEN)
            .expect("the layer table's grid is a valid constant");
        let peak = tables
            .iter()
            .flat_map(|table| table.iter())
            .fold(0.0_f64, |a, &b| a.max(b));
        let channels: [Spectrum; 3] = tables.map(|table| {
            let mut channel = Spectrum::filled(native.clone(), 0.0);
            for (value, sample) in channel.values_mut().iter_mut().zip(table.iter()) {
                *value = sample / peak;
            }
            channel.resampled(grid)
        });
        Self {
            name: name.to_owned(),
            channels,
        }
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

/// Piecewise Gaussian used by the Wyman fit: different width either side of the
/// peak.
fn lobe(wavelength: f64, peak: f64, left: f64, right: f64) -> f64 {
    let width = if wavelength < peak { left } else { right };
    let z = (wavelength - peak) / width;
    (-0.5 * z * z).exp()
}

/// The Wyman, Sloan and Shirley (2013) approximation of the CIE 1931 2 degree
/// colour matching functions, evaluated at one wavelength.
#[must_use]
pub fn cie1931_xyz(wavelength: f64) -> [f64; 3] {
    let x = 1.056 * lobe(wavelength, 599.8, 37.9, 31.0)
        + 0.362 * lobe(wavelength, 442.0, 16.0, 26.7)
        - 0.065 * lobe(wavelength, 501.1, 20.4, 26.2);
    let y =
        0.821 * lobe(wavelength, 568.8, 46.9, 40.5) + 0.286 * lobe(wavelength, 530.9, 16.3, 31.1);
    let z =
        1.217 * lobe(wavelength, 437.0, 11.8, 36.0) + 0.681 * lobe(wavelength, 459.0, 26.0, 13.8);
    [x, y, z]
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A film stock's own layers are used, not the default film's.
    ///
    /// The two films here differ only in which layer is which, so a context
    /// that quietly kept the built-in table would answer both the same way.
    #[test]
    fn a_stocks_layers_are_the_ones_it_responds_with() {
        let grid = Spectrum::uniform(380.0, 5.0, 71).unwrap();
        let default = Sensor::film_layers(&grid);
        assert_eq!(default.name(), "vision3-500t");

        // Blue light: the default film's blue-sensitive layer is the third.
        let blue = {
            let mut spectrum = Spectrum::filled(grid.clone(), 0.0);
            let index = ((450.0 - 380.0) / 5.0) as usize;
            spectrum.values_mut()[index] = 1.0;
            spectrum
        };
        let response = default.respond(&blue);
        assert!(
            response[2] > 10.0 * response[0] && response[2] > 10.0 * response[1],
            "{response:?}"
        );

        // Swap the tables: now the same light must land in channel 0.
        let swapped: [[f64; layers::LEN]; 3] = [
            layers::CHANNELS[2],
            layers::CHANNELS[1],
            layers::CHANNELS[0],
        ];
        let other = Sensor::film_layers_from(&grid, "swapped", &swapped);
        let response = other.respond(&blue);
        assert_eq!(other.name(), "swapped");
        assert!(
            response[0] > 10.0 * response[2],
            "the swapped film should see blue through its first channel: {response:?}"
        );
    }

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
    fn the_observer_peaks_where_it_should() {
        // The luminance function peaks near 555 nm.
        let peak = (380..=730)
            .step_by(5)
            .max_by(|a, b| cie1931_xyz(f64::from(*a))[1].total_cmp(&cie1931_xyz(f64::from(*b))[1]))
            .unwrap();
        assert!((545..=565).contains(&peak), "peak at {peak} nm");
    }

    /// Channel 0 sees red, channel 2 sees blue — in every constructor. The two
    /// generic cameras disagreed about this for as long as both the camera and
    /// the film layers were listed blue-first, because red in still came out red.
    #[test]
    fn every_constructor_indexes_its_channels_red_to_blue() {
        let grid = Spectrum::uniform(380.0, 5.0, 71).unwrap();
        let band = |centre: f64| {
            let mut spectrum = Spectrum::filled(grid.clone(), 0.0);
            for (index, value) in spectrum.values_mut().iter_mut().enumerate() {
                let wavelength = grid.start_nm() + grid.step_nm() * index as f64;
                *value = (-0.5 * ((wavelength - centre) / 12.0).powi(2)).exp();
            }
            spectrum
        };
        let (red, blue) = (band(650.0), band(450.0));
        for sensor in [
            Sensor::generic_camera(&grid),
            Sensor::generic_camera_shifted(&grid, 0.0),
        ] {
            let at_red = sensor.respond(&red);
            let at_blue = sensor.respond(&blue);
            assert!(
                at_red[0] > 5.0 * at_blue[0],
                "{}: red channel reads {:.4} from red and {:.4} from blue",
                sensor.name(),
                at_red[0],
                at_blue[0]
            );
            assert!(
                at_blue[2] > 5.0 * at_red[2],
                "{}: blue channel reads {:.4} from blue and {:.4} from red",
                sensor.name(),
                at_blue[2],
                at_red[2]
            );
        }
    }

    /// The sRGB basis is exact and is not a sensor: it has to keep the negative
    /// lobes that the inverse matrix produces, or it is no longer sRGB.
    #[test]
    fn the_srgb_basis_has_negative_lobes() {
        let grid = Spectrum::uniform(380.0, 5.0, 71).unwrap();
        let sensor = Sensor::srgb(&grid);
        let red = sensor.channels()[0].min();
        let blue = sensor.channels()[2].min();
        assert!(red < -0.1, "red basis minimum {red}");
        assert!(blue < -0.1, "blue basis minimum {blue}");
        assert_eq!(sensor.name(), "srgb-primaries");
    }

    #[test]
    fn channels_must_share_a_grid() {
        let a = Spectrum::uniform(380.0, 10.0, 36).unwrap();
        let b = Spectrum::uniform(380.0, 5.0, 71).unwrap();
        assert!(Sensor::new("bad", [a.clone(), b, a]).is_err());
    }
}
