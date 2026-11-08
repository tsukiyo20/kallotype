//! Development kinetics.
//!
//! The one dimension the reference model does not have: how long the film sat
//! in the developer, and at what temperature. Development is a diffusion-limited
//! reaction, so the useful approximations are all saturating functions of an
//! *effective* time that itself follows an Arrhenius-like temperature law.
//!
//! ```
//! use kallotype_core::DevelopmentParams;
//!
//! let normal = DevelopmentParams::default();
//! let pushed = DevelopmentParams { time_min: 12.0, ..normal };
//! assert!(pushed.gamma_factor() > normal.gamma_factor());
//! ```
//!
//! The constants below were chosen so the model behaves like a real process over
//! the usual 3–15 minute range. They are now **fitted to a measured curve
//! family**: ILFORD DELTA 400's contrast-against-time graphs (publication
//! `d400_a.pdf`, page 5), two temperatures and four developers. Fitted jointly to
//! the ID-11 pair — 15 points, 20 °C and 24 °C — this form reproduces the
//! measured contrast to **0.005**, and the fitted numbers are not the ones the
//! priors guessed:
//!
//! | | prior | fitted |
//! |---|---|---|
//! | `gamma_inf` | 1.00 | 2.20 |
//! | `gamma_0` | 0.15 | 0.18 |
//! | `tau_min` | 4.5 | **39.0** |
//! | `q10` | 2.00 | 1.70 |
//!
//! `tau` is the one that mattered. At 4.5 minutes the prior model reaches 94 % of
//! its final contrast by twelve minutes; the film is at 47 % at six and 71 % at
//! twelve. A push built on the prior was a saturated curve pushed further, not a
//! curve that is still building.
//!
//! What is still a prior: `fog_rate` and `speed_gain`. No sheet in the archive
//! plots fog or the speed point against development time, and inventing a
//! measurement for them would be worse than saying so.

/// How a development time and temperature move the characteristic curve.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DevelopmentParams {
    /// Development time, in minutes.
    pub time_min: f64,
    /// Developer temperature, in degrees Celsius.
    pub temp_c: f64,
    /// Time that produces the stock's nominal curve (usually the data-sheet time).
    pub reference_time_min: f64,
    /// Temperature at which the data-sheet time applies.
    pub reference_temp_c: f64,
    /// Rate multiplier per 10 °C. 1.70, fitted to DELTA 400's time-temperature
    /// pair; the photographer's rule of thumb says two and the measurement says
    /// less.
    pub q10: f64,
    /// Contrast the process converges to as time goes to infinity.
    pub gamma_inf: f64,
    /// Contrast a barely-developed strip would show.
    pub gamma_0: f64,
    /// Time constant of the contrast build-up, in effective minutes.
    pub tau_min: f64,
    /// Base + fog growth per sqrt(effective minute).
    pub fog_rate: f64,
    /// Speed gain per natural-log unit of over-development.
    pub speed_gain: f64,
}

impl Default for DevelopmentParams {
    fn default() -> Self {
        Self {
            time_min: 6.5,
            temp_c: 20.0,
            reference_time_min: 6.5,
            reference_temp_c: 20.0,
            q10: 1.70,
            gamma_inf: 2.20,
            gamma_0: 0.18,
            tau_min: 39.0,
            fog_rate: 0.02,
            speed_gain: 0.06,
        }
    }
}

impl DevelopmentParams {
    /// Time-temperature compensated development time, in minutes.
    #[must_use]
    pub fn effective_time_min(&self) -> f64 {
        let t = self.time_min.max(0.0);
        t * self.q10.powf((self.temp_c - self.reference_temp_c) / 10.0)
    }

    /// Effective time of a nominal development: the normalisation anchor.
    #[must_use]
    pub fn reference_effective_time_min(&self) -> f64 {
        self.reference_time_min.max(1e-6)
    }

    fn contrast_at(&self, effective_time: f64) -> f64 {
        self.gamma_inf + (self.gamma_0 - self.gamma_inf) * (-effective_time / self.tau_min).exp()
    }

    /// Multiplier on the stock's nominal contrast: 1.0 at the reference development.
    #[must_use]
    pub fn gamma_factor(&self) -> f64 {
        let reference = self.contrast_at(self.reference_effective_time_min());
        if reference.abs() < 1e-9 {
            return 1.0;
        }
        self.contrast_at(self.effective_time_min()) / reference
    }

    /// Change in `d_min` (base + fog) relative to the reference development.
    #[must_use]
    pub fn fog_delta(&self) -> f64 {
        let t = self.effective_time_min().max(0.0).sqrt();
        let reference = self.reference_effective_time_min().max(0.0).sqrt();
        self.fog_rate * (t - reference)
    }

    /// Shift of the speed point in log10 exposure; negative means faster.
    #[must_use]
    pub fn speed_delta(&self) -> f64 {
        let ratio = self.effective_time_min() / self.reference_effective_time_min();
        -self.speed_gain * ratio.max(1e-9).ln()
    }

    /// Apply this development to a nominal curve.
    #[must_use]
    pub fn apply_to(
        &self,
        nominal: crate::curve::CharacteristicCurve,
    ) -> crate::curve::CharacteristicCurve {
        crate::curve::CharacteristicCurve {
            d_min: (nominal.d_min + self.fog_delta()).max(0.0),
            d_max: nominal.d_max,
            gamma: nominal.gamma * self.gamma_factor(),
            log_e0: nominal.log_e0 + self.speed_delta(),
            toe_transition: nominal.toe_transition,
            shoulder_transition: nominal.shoulder_transition,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::curve::CharacteristicCurve;

    #[test]
    fn reference_development_is_the_identity() {
        let d = DevelopmentParams::default();
        assert!((d.gamma_factor() - 1.0).abs() < 1e-12);
        assert!(d.fog_delta().abs() < 1e-12);
        assert!(d.speed_delta().abs() < 1e-12);
    }

    #[test]
    fn longer_development_builds_contrast_and_fog() {
        let base = DevelopmentParams::default();
        let long = DevelopmentParams {
            time_min: 12.0,
            ..base
        };
        assert!(long.gamma_factor() > 1.0);
        assert!(long.fog_delta() > 0.0);
        assert!(long.speed_delta() < 0.0, "over-development gains speed");
    }

    #[test]
    fn temperature_trades_against_time() {
        let base = DevelopmentParams::default();
        let warm_short = DevelopmentParams {
            time_min: base.reference_time_min / base.q10,
            temp_c: 30.0,
            ..base
        };
        // +10 °C divides the time by q10 for the same result.
        assert!((warm_short.gamma_factor() - 1.0).abs() < 1e-6);
    }

    /// The model against the sheet it was fitted to: DELTA 400 in ID-11 at
    /// 20 °C, referenced to the six-and-a-half minute development Ilford prints
    /// as normal. Contrast at 12 and 18 minutes is 1.46 and 1.89 times the
    /// contrast at 6.5, and the model reproduces both to 0.01.
    #[test]
    fn the_gamma_factor_matches_the_measured_contrast_time_curve() {
        let base = DevelopmentParams {
            reference_time_min: 6.5,
            ..DevelopmentParams::default()
        };
        let at = |time_min: f64| DevelopmentParams { time_min, ..base }.gamma_factor();
        assert!((at(12.0) - 1.46).abs() < 0.02, "12 min: {}", at(12.0));
        assert!((at(18.0) - 1.89).abs() < 0.02, "18 min: {}", at(18.0));
        assert!(at(6.5) - 1.0 < 1e-12);
    }

    #[test]
    fn curve_moves_in_the_documented_direction() {
        let nominal = CharacteristicCurve::new(0.2, 2.3, 0.6, -0.75);
        let pushed = DevelopmentParams {
            time_min: 12.0,
            ..DevelopmentParams::default()
        }
        .apply_to(nominal);
        assert!(pushed.gamma > nominal.gamma);
        assert!(pushed.d_min > nominal.d_min);
        assert!(pushed.log_e0 < nominal.log_e0);
    }
}
