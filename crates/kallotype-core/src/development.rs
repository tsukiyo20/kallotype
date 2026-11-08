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
//! # The ladder, and the three quantities it measures
//!
//! DELTA 400's chart plots contrast against time and nothing else. TRI-X 400's
//! printed page 12 plots the whole curve four times — D-76, large tank, 20 °C,
//! 1-minute agitation, at 6, 8, 10 and 12 minutes — which is the first ladder in
//! the archive that can test everything the model does with time. Digitised and
//! fitted (see `docs/measurements/2026-11-08-development-time.md`), it gives:
//!
//! | quantity | measured | this model |
//! |---|---|---|
//! | contrast, 6 to 12 min | 0.546 → 0.824 | **+2.5 %** at 8 and 10 min, +1.3 % at 12 |
//! | base plus fog | +0.078 per √min | `fog_rate` |
//! | ceiling (the highest density drawn, above base) | +0.91 per √min | `d_max_gain` |
//! | speed | −0.44 per ln(t / t_ref) | `speed_gain` |
//!
//! The last three were priors until this sheet. The ceiling is the one that
//! mattered most: the current model held it fixed while the film's rises by
//! nearly a whole density between six and twelve minutes, and a pushed render
//! was therefore 0.2 to 0.6 of a density flat across its top. With all three
//! fitted, the four curves of the ladder are reproduced to **0.03 of a density**
//! rms; before, the pushed rungs were off by 0.21, 0.41 and 0.62.
//!
//! What the ladder also shows, and this model does not do: the film's **toe
//! sharpens** as development goes on — the fitted corner rate rises from 3 to 8
//! between six and twelve minutes — while `toe_transition` is carried through
//! unchanged. That is why the model's 0.10-over-fog crossing sits 0.1 to 0.3 of
//! a decade left of the sheet's even when the curves agree: the crossing lives
//! in the toe, and the toe is the one thing the ladder measures that the model
//! cannot express yet. The four rungs constrain a toe-sharpening term too weakly
//! to fit one, so it is written down instead.

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
    /// Growth of the curve's ceiling, above base, per sqrt(effective minute).
    ///
    /// A negative's maximum density is not fixed: TRI-X 400's sheet draws the
    /// same film at 6, 8, 10 and 12 minutes and the top of the curve rises by
    /// 0.34, 0.65 and 0.94 of a density. Holding it still made every pushed
    /// render flat across the highlights by more than half a density.
    pub d_max_gain: f64,
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
            fog_rate: 0.078,
            d_max_gain: 0.91,
            speed_gain: 0.44,
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

    /// Growth of the ceiling above base, relative to the reference development.
    #[must_use]
    pub fn d_max_delta(&self) -> f64 {
        let t = self.effective_time_min().max(0.0).sqrt();
        let reference = self.reference_effective_time_min().max(0.0).sqrt();
        self.d_max_gain * (t - reference)
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
            d_max: nominal.d_max + self.d_max_delta(),
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

    /// TRI-X 400's D-76 ladder, printed page 12: one film, four times.
    ///
    /// `(minutes, gamma, fog, ceiling above base, log_e0)` as digitised from the
    /// sheet — see `docs/measurements/2026-11-08-development-time.md`. The
    /// contrast column is a cross-stock check: the shape was fitted on DELTA 400
    /// in ID-11, a different film in a different developer.
    #[test]
    fn the_trix400_ladder_is_reproduced() {
        const LADDER: [(f64, f64, f64, f64, f64); 4] = [
            (6.0, 0.5464, 0.0000, 1.4862, -1.0910),
            (8.0, 0.6290, 0.0252, 1.8240, -1.2210),
            (10.0, 0.7212, 0.0462, 2.1347, -1.3110),
            (12.0, 0.8236, 0.0874, 2.4215, -1.4010),
        ];
        let nominal = CharacteristicCurve::new(0.0, 1.4862, 0.5464, -1.0910).with_corners(3.0, 8.0);
        for (minutes, gamma, fog, ceiling, log_e0) in LADDER {
            let curve = DevelopmentParams {
                time_min: minutes,
                reference_time_min: 6.0,
                ..DevelopmentParams::default()
            }
            .apply_to(nominal);
            assert!(
                (curve.gamma - gamma).abs() < 0.03,
                "{minutes} min: gamma {:.4} against {gamma:.4}",
                curve.gamma
            );
            assert!(
                (curve.d_min - fog).abs() < 0.012,
                "{minutes} min: fog {:.4} against {fog:.4}",
                curve.d_min
            );
            assert!(
                (curve.d_max - ceiling).abs() < 0.02,
                "{minutes} min: ceiling {:.4} against {ceiling:.4}",
                curve.d_max
            );
            assert!(
                (curve.log_e0 - log_e0).abs() < 0.01,
                "{minutes} min: log_e0 {:.4} against {log_e0:.4}",
                curve.log_e0
            );
        }
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
