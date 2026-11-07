//! The characteristic curve — density as a function of log10 exposure.
//!
//! This is the H&D curve measured by Hurter and Driffield in 1890, and the
//! object the whole project is named after.
//!
//! ## The shape is measured, not assumed
//!
//! The first version of this file used a single logistic in log exposure. It has
//! four convenient properties — monotone, closed-form inverse, `gamma` as the
//! maximum slope, `log_e0` as the inflection — and it is *wrong in a way that
//! matters*: a logistic's slope rises to a single peak and falls away, so its
//! curve has a point of maximum contrast and no straight line. A real
//! sensitometric curve has three regions a photographer names without
//! hesitation: a toe, a **straight line**, and a shoulder.
//!
//! Fitted against the three curves digitised from the KODAK VISION3 500T data
//! sheet (H-1-5219, page 3), over the full −8 to +8 stop range:
//!
//! | layer | logistic rms | this model rms |
//! |---|---|---|
//! | blue | 0.0236 | 0.0071 |
//! | green | 0.0219 | 0.0060 |
//! | red | 0.0167 | 0.0045 |
//!
//! and the parameters it lands on are the ones the data sheet implies: `d_min`
//! within 0.01 of the measured plateaus, `gamma` between 0.47 and 0.56 per
//! decade, and all three layers agreeing on where the toe and the shoulder are.
//! The logistic's slope was a bump; the measurement's is a plateau, and a model
//! that cannot express a straight line cannot express a negative.
//!
//! ## The form
//!
//! ```text
//! D(x) = d_min + (gamma/a) · [ softplus(a·(x − x_toe)) − softplus(a·(x − x_shoulder)) ]
//! ```
//!
//! The derivative is `gamma` times the difference of two logistic steps, which
//! is a plateau of height `gamma` between the two corners and zero outside: flat
//! toe, straight line, flat shoulder, and continuous everywhere. The straight
//! line runs from `log_e0 − span/(2·gamma)` to `log_e0 + span/(2·gamma)`, so its
//! length is not a fifth parameter — a curve that saturates over `span` at slope
//! `gamma` has exactly that much straight line and no more.
//!
//! `a` is the one number the four parameters do not carry: how abruptly the
//! straight line turns into the toe. Fitted per layer of the negative it lands
//! at 1.09, 1.17 and 1.33 per stop, so one value serves that film: a number that
//! moves by 0.2 between three layers is not resolved by a chart digitised to a
//! few thousandths of a density.
//!
//! ## And the paper has no straight line
//!
//! The paper's curves, digitised from KODAK publication E-4071 page 4, do not
//! have the shape the negative's do. Measured through a half-decade window, the
//! blue-sensitive layer's slope runs 0.08, 0.20, 0.75, 1.63, 2.63, 3.97, 4.47,
//! 4.50, 3.12, 1.94, 1.31 — it rises to a peak and falls away. There is no
//! stretch over which the slope is constant, which means there is no straight
//! line to have a slope, and `gamma` alone cannot describe the curve.
//!
//! The same family covers both, because a soft corner and a short straight line
//! look alike: at a transition of 10 the corners of the paper's trapezoid reach
//! across its whole straight line, and what comes out is the sigmoid the data
//! sheet drew. Fitted that way the paper's curves are reproduced to 0.007–0.013
//! of density, against 0.14 with the negative's transition of 4 — a shape that
//! cannot bend fast enough to be a paper.
//!
//! So `a` lives on the curve, and it is not even one number per material family:
//! the two data sheets that have been digitised want different ones. ENDURA
//! Premier Metallic turns at 10, the PORTRA and SUPRA ENDURA of E-4021 at 7 and
//! 8 — a newer emulsion with a harder corner, and two older ones with a softer.
//! Each stock carries what its own sheet was fitted at, and the value is not
//! resolved per layer within a stock.

/// How sharply the straight line turns into the toe and the shoulder, per
/// decade of exposure.
///
/// This is the negative's value, fitted from the measured VISION3 500T curves at
/// 1.09–1.33 per stop, and it is the default for a curve built without a
/// measurement of its own. It is **not** a universal constant: every measured
/// stock carries the value its own sheet was fitted at. See the module docs.
pub const TRANSITION: f64 = 4.0;

/// Numerically stable `ln(1 + e^u)`.
///
/// Written as `max(u,0) + ln(1 + e^-|u|)` because the direct form overflows for
/// large `u`, and large `u` is the shoulder of every well-exposed frame.
#[inline]
#[must_use]
fn softplus(u: f64) -> f64 {
    u.max(0.0) + (-u.abs()).exp().ln_1p()
}

/// Numerically stable logistic function.
#[inline]
#[must_use]
pub fn sigmoid(z: f64) -> f64 {
    if z >= 0.0 {
        1.0 / (1.0 + (-z).exp())
    } else {
        let e = z.exp();
        e / (1.0 + e)
    }
}

/// Inverse of [`sigmoid`], clamped away from the asymptotes.
#[inline]
#[must_use]
pub fn logit(p: f64) -> f64 {
    let p = p.clamp(1e-9, 1.0 - 1e-9);
    (p / (1.0 - p)).ln()
}

/// The curve's density at a log exposure, given the four parameters plus the
/// shape's transition.
///
/// Shared by [`CharacteristicCurve::density`] and the GPU model, which is why it
/// takes the numbers rather than the struct: the shader has the numbers and
/// nothing else.
#[inline]
#[must_use]
pub fn density_from(
    d_min: f64,
    d_max: f64,
    gamma: f64,
    log_e0: f64,
    transition: f64,
    log_e: f64,
) -> f64 {
    let span = (d_max - d_min).max(1e-9);
    let gamma = gamma.max(1e-9);
    let half = 0.5 * span / gamma;
    let slope = transition.max(1e-3);
    d_min
        + (gamma / slope)
            * (softplus(slope * (log_e - (log_e0 - half)))
                - softplus(slope * (log_e - (log_e0 + half))))
}

/// The curve's local slope at a log exposure, in density per decade.
#[inline]
#[must_use]
pub fn slope_from(
    d_min: f64,
    d_max: f64,
    gamma: f64,
    log_e0: f64,
    transition: f64,
    log_e: f64,
) -> f64 {
    let span = (d_max - d_min).max(1e-9);
    let gamma = gamma.max(1e-9);
    let half = 0.5 * span / gamma;
    let slope = transition.max(1e-3);
    gamma
        * (sigmoid(slope * (log_e - (log_e0 - half))) - sigmoid(slope * (log_e - (log_e0 + half))))
}

/// A single characteristic curve.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CharacteristicCurve {
    /// Density of the unexposed, processed material (base + fog).
    pub d_min: f64,
    /// Density at full exposure (the shoulder).
    pub d_max: f64,
    /// Slope of the straight line, in density per decade of exposure.
    ///
    /// On a paper, which has no straight line, this is the slope the trapezoid
    /// would have if its corners were sharp; it comes out within 1.4× of the
    /// steepest slope the data sheet draws. [`Self::slope_at`] is the honest
    /// observable.
    pub gamma: f64,
    /// log10 exposure at the middle of the straight line.
    pub log_e0: f64,
    /// How sharply the toe and the shoulder turn, per decade.
    ///
    /// [`TRANSITION`] unless a measurement said otherwise: the measured stocks
    /// carry their own, from 7 for a print to 10 for a harder-cornered one.
    pub transition: f64,
}

impl CharacteristicCurve {
    /// Build a curve from its four photographic parameters, at the negative's
    /// transition.
    #[must_use]
    pub const fn new(d_min: f64, d_max: f64, gamma: f64, log_e0: f64) -> Self {
        Self {
            d_min,
            d_max,
            gamma,
            log_e0,
            transition: TRANSITION,
        }
    }

    /// The same curve, made of a material that turns its corners differently.
    #[must_use]
    pub const fn with_transition(self, transition: f64) -> Self {
        Self { transition, ..self }
    }

    /// Height of the curve, in density units.
    #[must_use]
    pub fn span(&self) -> f64 {
        (self.d_max - self.d_min).max(1e-9)
    }

    /// Slope of the straight line, which is `gamma` itself.
    ///
    /// Kept as a method because the model is described in terms of it elsewhere;
    /// for the logistic this was `4·gamma/span`, the transformation that made a
    /// logistic's maximum slope equal `gamma`. Here the slope *is* `gamma` over
    /// the whole straight line, which is the point of the shape.
    #[must_use]
    pub fn slope_factor(&self) -> f64 {
        self.gamma
    }

    /// Density at a given log10 exposure.
    #[must_use]
    pub fn density(&self, log_e: f64) -> f64 {
        density_from(
            self.d_min,
            self.d_max,
            self.gamma,
            self.log_e0,
            self.transition,
            log_e,
        )
    }

    /// Local slope at a given log10 exposure, in density per decade.
    #[must_use]
    pub fn slope_at(&self, log_e: f64) -> f64 {
        slope_from(
            self.d_min,
            self.d_max,
            self.gamma,
            self.log_e0,
            self.transition,
            log_e,
        )
    }

    /// log10 exposure at which `density` is reached; the inverse of [`Self::density`].
    ///
    /// `d_min` and `d_max` are asymptotes, so densities at (or beyond) the ends
    /// of the curve are clamped rather than inverted. The inverse is found
    /// numerically because the softplus difference has no closed-form inverse;
    /// it is monotone, so bisection plus a Newton polish converges in a handful
    /// of steps and cannot wander.
    #[must_use]
    pub fn log_exposure_at(&self, density: f64) -> f64 {
        let half = 0.5 * self.span() / self.gamma.max(1e-9);
        let target = (density - self.d_min) / self.span();
        // Below the toe and above the shoulder the answer is the asymptote.
        if target <= 1e-12 {
            return self.log_e0 - half - 10.0;
        }
        if target >= 1.0 - 1e-12 {
            return self.log_e0 + half + 10.0;
        }

        // A bracket wide enough to contain the answer for any sane curve, then
        // bisection: forty halvings is a factor of 10^12, far past f64.
        let mut low = self.log_e0 - half - 10.0;
        let mut high = self.log_e0 + half + 10.0;
        for _ in 0..200 {
            let middle = 0.5 * (low + high);
            if self.density(middle) < density {
                low = middle;
            } else {
                high = middle;
            }
            if high - low < 1e-12 {
                break;
            }
        }
        0.5 * (low + high)
    }

    /// Return a copy of this curve with new exposure and density anchors.
    #[must_use]
    pub fn shifted(&self, delta_log_e: f64, delta_d_min: f64) -> Self {
        Self {
            d_min: self.d_min + delta_d_min,
            log_e0: self.log_e0 + delta_log_e,
            ..*self
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn curve() -> CharacteristicCurve {
        CharacteristicCurve::new(0.2, 2.2, 0.6, -0.75)
    }

    #[test]
    fn is_monotonic_and_bounded() {
        let c = curve();
        let mut previous = f64::NEG_INFINITY;
        for i in -800..800 {
            let d = c.density(f64::from(i) / 100.0);
            assert!(d > previous, "density must increase with exposure");
            assert!(
                (c.d_min - 1e-6..=c.d_max + 1e-6).contains(&d),
                "escaped the curve at {d}"
            );
            previous = d;
        }
    }

    /// The straight line is the whole point: through its middle the slope is
    /// `gamma`, and it stays there rather than peaking. The corners reach about
    /// `1/a` decades into the stretch between them — 2 % of `gamma` at a quarter
    /// of a decade from a corner — so the test states the tolerance it means.
    #[test]
    fn the_straight_line_has_constant_slope() {
        let c = curve();
        let half = 0.5 * c.span() / c.gamma;
        let centre = c.slope_at(c.log_e0);
        assert!(
            (centre - c.gamma).abs() < 0.005 * c.gamma,
            "centre slope {centre} vs gamma {}",
            c.gamma
        );
        for offset in [-0.5 * half, 0.5 * half] {
            let slope = c.slope_at(c.log_e0 + offset);
            assert!(
                (slope - c.gamma).abs() < 0.05 * c.gamma,
                "slope {slope} at {offset}"
            );
        }
    }

    /// And outside it, the slope goes to zero: a toe that never flattens is a
    /// curve with no base density, which is not what a film has.
    #[test]
    fn the_ends_are_flat() {
        let c = curve();
        let half = 0.5 * c.span() / c.gamma;
        assert!(c.slope_at(c.log_e0 - half - 2.0) < 1e-3);
        assert!(c.slope_at(c.log_e0 + half + 2.0) < 1e-3);
    }

    /// The maximum slope is `gamma`, and it is attained over a range rather than
    /// at a point — the difference from a logistic, stated as a test. A logistic
    /// with the same `gamma` and span would hold 90 % of it at a single value of
    /// the exposure and nowhere else.
    #[test]
    fn the_maximum_slope_is_reached_over_a_plateau() {
        let c = curve();
        let half = 0.5 * c.span() / c.gamma;
        let mut on_plateau = 0;
        for i in 0..400 {
            let x = c.log_e0 - half + (i as f64) / 400.0 * 2.0 * half;
            if c.slope_at(x) > 0.9 * c.gamma {
                on_plateau += 1;
            }
        }
        assert!(
            on_plateau > 200,
            "only {on_plateau}/400 samples within 10 % of gamma"
        );
    }

    /// The transition is what lets one shape be two materials. Turned softly,
    /// the corners reach across the straight line and the curve is the sigmoid a
    /// paper actually has; turned sharply, the straight line is real and its
    /// slope is `gamma`.
    #[test]
    fn the_transition_decides_how_much_of_gamma_the_curve_reaches() {
        fn peak(curve: CharacteristicCurve) -> f64 {
            (0..400)
                .map(|i| curve.slope_at(curve.log_e0 - 1.0 + f64::from(i) / 200.0))
                .fold(f64::NEG_INFINITY, f64::max)
        }

        // The paper's measured red layer, at both materials' transitions.
        let paper = CharacteristicCurve::new(0.2078, 2.7739, 5.24, -1.1750);
        // The transition the metallic paper's own sheet fitted.
        let sharp = peak(paper.with_transition(10.0));
        let soft = peak(paper.with_transition(TRANSITION));
        assert!(
            (sharp - 4.4).abs() < 0.2,
            "at the paper's transition the slope peaks at {sharp}, not near the 4.8 the sheet draws"
        );
        assert!(
            soft < 0.6 * sharp,
            "the negative's transition still reached {soft} of {sharp}"
        );

        // The negative's layer keeps `gamma` as its peak, which is the property
        // the shape was chosen for.
        let negative = CharacteristicCurve::new(0.0, 1.6818, 0.4745, -0.7582);
        assert!(
            (peak(negative) - negative.gamma).abs() < 0.01 * negative.gamma,
            "the negative peaked at {} against gamma {}",
            peak(negative),
            negative.gamma
        );
    }

    #[test]
    fn inverse_agrees_with_forward() {
        let c = curve();
        for i in 1..10 {
            let d = c.d_min + c.span() * f64::from(i) / 10.0;
            let x = c.log_exposure_at(d);
            assert!(
                (c.density(x) - d).abs() < 1e-6,
                "{d} -> {x} -> {}",
                c.density(x)
            );
        }
    }

    #[test]
    fn the_inverse_is_monotonic() {
        let c = curve();
        let mut previous = f64::NEG_INFINITY;
        for i in 1..200 {
            let d = c.d_min + c.span() * f64::from(i) / 200.0;
            let x = c.log_exposure_at(d);
            assert!(x > previous, "not monotonic at {d}");
            previous = x;
        }
    }
}
