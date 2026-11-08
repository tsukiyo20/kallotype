//! A dye formed by more than one emulsion — ADR 0017, first piece.
//!
//! The model's oldest assumption is that a dye and an emulsion are the same
//! thing: blue light forms cyan, green magenta, red yellow, one apiece. The
//! four-layer negative breaks it — PRO 400H has a blue-sensitive layer *and* a
//! cyan-sensitive one, stacked, both forming cyan dye — and the honest model is
//! the general one: a dye declares the emulsions that feed it.
//!
//! The physics is short. Each emulsion has its own spectral sensitivity and its
//! own characteristic curve, because they are separate crystals with separate
//! development. Their densities add, because both sit in the same stack and
//! both make the same dye. A dye with one emulsion is exactly the model that
//! came before, which is why nothing else has to change to adopt this.
//!
//! This module is the arithmetic only; wiring it into `FilmStock` and the two
//! exposure paths is the next commit.

/// First wavelength of [`Emulsion::sensitivity`], in nanometres.
///
/// The table and the step travel with the type rather than with a stock,
/// because two stocks pasted from two sheets must still mean the same grid.
pub const SENSITIVITY_START_NM: f64 = 380.0;

/// Spacing of [`Emulsion::sensitivity`], in nanometres.
pub const SENSITIVITY_STEP_NM: f64 = 10.0;

/// One sensitising emulsion feeding a dye.
#[derive(Debug, Clone, Copy)]
pub struct Emulsion {
    /// Its characteristic curve, as `(d_min, d_max, gamma, log_e0)`.
    pub curve: [f64; 4],
    /// How sharply it turns.
    pub transition: f64,
    /// Relative sensitivity against wavelength, starting at 380 nm in 10 nm
    /// steps. A layer that does not see a wavelength stores zero there.
    pub sensitivity: &'static [f32],
}

impl Emulsion {
    /// The curve those four numbers describe.
    #[must_use]
    pub fn characteristic(&self) -> crate::curve::CharacteristicCurve {
        crate::curve::CharacteristicCurve::new(
            self.curve[0],
            self.curve[1],
            self.curve[2],
            self.curve[3],
        )
        .with_transition(self.transition)
    }

    /// The density this emulsion develops at one log exposure.
    #[must_use]
    pub fn density(&self, log_exposure: f64) -> f64 {
        self.characteristic().density(log_exposure)
    }
}

/// The log exposure one emulsion receives from a spectral radiance.
///
/// The sensitivity table and the radiance share a grid; the product is summed
/// and the result is the relative exposure, normalised so a sensitivity of one
/// everywhere under a radiance of one gives an exposure of one. This is the
/// same integral the three-layer spectral path already does — it lives here
/// because a fourth layer needs a fourth integral and the code that owns the
/// layer should own its arithmetic.
///
/// `step_nm` multiplies the sum so two grids of different pitch agree, which is
/// the one thing a table alone cannot say.
#[must_use]
pub fn log_exposure(sensitivity: &[f64], radiance: &[f64], step_nm: f64) -> f64 {
    if sensitivity.is_empty() || radiance.is_empty() || step_nm <= 0.0 {
        return f64::NEG_INFINITY;
    }
    let total: f64 = sensitivity
        .iter()
        .zip(radiance)
        .map(|(s, r)| s * r)
        .sum::<f64>()
        * step_nm;
    if total > 0.0 {
        total.ln()
    } else {
        f64::NEG_INFINITY
    }
}

/// A cyan-sensitive layer that releases development inhibitor instead of dye.
///
/// Fuji's fourth layer was introduced with REALA and described in 1989 as
/// sensitive to cyan light around 470–540 nm, releasing development inhibitors
/// in proportion to exposure so that the red-sensitive layer is pulled back —
/// an inter-image effect approximating the negative lobe of the colour matching
/// functions. That is a different object from a second emulsion feeding a dye
/// (ADR 0017): it forms no density of its own, and its effect on a
/// characteristic curve is invisible, because a neutral wedge exposes it
/// uniformly and the inhibition is absorbed into the curve that was measured.
///
/// The table is on the model's own grid rather than the sheet's, because the
/// digitisation already produces that grid and a fourth resampling step would
/// be a place for the two to disagree.
#[derive(Debug, Clone, Copy)]
pub struct InhibitorLayer {
    /// Relative sensitivity against wavelength, 380–730 nm at 5 nm.
    pub sensitivity: &'static [f64; crate::spectral::GRID_LEN],
}

/// A dye, and the emulsions that form it.
///
/// Two is the bound the sheets need: four-layer films add a second cyan
/// emulsion, and no data sheet draws three on one dye.
#[derive(Debug, Clone, Copy)]
pub struct Dye {
    /// The emulsions feeding this dye; `None` entries are unused.
    pub emulsions: [Option<Emulsion>; 2],
}

impl Dye {
    /// A dye with one emulsion — every stock before ADR 0017.
    #[must_use]
    pub const fn single(emulsion: Emulsion) -> Self {
        Self {
            emulsions: [Some(emulsion), None],
        }
    }

    /// How many emulsions feed it.
    #[must_use]
    pub fn count(&self) -> usize {
        self.emulsions
            .iter()
            .filter(|layer| layer.is_some())
            .count()
    }

    /// The dye's density at the log exposures its emulsions see.
    ///
    /// The sum is over densities, not exposures: two emulsions at different
    /// exposures do not add up to one emulsion at their sum, which is the
    /// shortcut this model exists to refuse.
    #[must_use]
    pub fn density(&self, log_exposure: &[f64]) -> f64 {
        self.emulsions
            .iter()
            .flatten()
            .zip(log_exposure)
            .map(|(emulsion, exposure)| emulsion.density(*exposure))
            .sum()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn emulsion(d_min: f64, d_max: f64) -> Emulsion {
        Emulsion {
            curve: [d_min, d_max, 1.0, 0.0],
            transition: 4.0,
            sensitivity: &[],
        }
    }

    /// One emulsion is the old model, exactly: this is the compatibility
    /// promise the whole change rests on.
    #[test]
    fn one_emulsion_is_the_old_model() {
        let dye = Dye::single(emulsion(0.0, 2.0));
        assert_eq!(dye.count(), 1);
        let one = dye.density(&[0.5]);
        let expected = crate::curve::density_from(0.0, 2.0, 1.0, 0.0, 4.0, 4.0, 0.5);
        assert!((one - expected).abs() < 1e-12);
        // A second exposure in the slice is ignored: one emulsion sees one.
        assert!((dye.density(&[0.5, 3.0]) - one).abs() < 1e-12);
    }

    /// Two emulsions add in density. If they added in exposure, a cyan layer
    /// at −1.0 and a blue layer at 0.0 would equal one layer at 1.0 — and the
    /// film's whole reason for a fourth layer would be lost.
    #[test]
    fn two_emulsions_add_in_density_not_in_exposure() {
        let dye = Dye {
            emulsions: [Some(emulsion(0.0, 2.0)), Some(emulsion(0.0, 2.0))],
        };
        assert_eq!(dye.count(), 2);
        let pair = dye.density(&[-1.0, 0.0]);
        let summed = emulsion(0.0, 2.0).density(-1.0) + emulsion(0.0, 2.0).density(0.0);
        assert!((pair - summed).abs() < 1e-12);
        let combined = emulsion(0.0, 2.0).density(1.0);
        assert!(
            (pair - combined).abs() > 0.05,
            "adding exposures would give {combined:.3}, adding densities gives {pair:.3}"
        );
    }

    /// The fourth layer's integral: flat radiance through a flat sensitivity
    /// gives the sum times the step, and a layer that sees nothing stays in
    /// the dark rather than dividing by zero.
    #[test]
    fn an_emulsions_exposure_is_the_sensitivity_against_the_light() {
        let sensitivity = [0.5; 8];
        let radiance = [2.0; 8];
        let exposure = log_exposure(&sensitivity, &radiance, 5.0);
        assert!((exposure - (0.5 * 2.0 * 8.0 * 5.0f64).ln()).abs() < 1e-12);
        assert_eq!(
            log_exposure(&sensitivity, &[0.0; 8], 5.0),
            f64::NEG_INFINITY
        );
        assert_eq!(log_exposure(&[], &radiance, 5.0), f64::NEG_INFINITY);
        // A finer grid with the same integral agrees, which is what `step_nm`
        // is for.
        let fine = log_exposure(&[0.5; 16], &[2.0; 16], 2.5);
        assert!((fine - exposure).abs() < 1e-12);
    }
}
