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
/// two corners' transitions.
///
/// Shared by [`CharacteristicCurve::density`] and the GPU model, which is why it
/// takes the numbers rather than the struct: the shader has the numbers and
/// nothing else.
///
/// The two transitions are the one thing the shape gained after it was first
/// written. A measured curve rarely turns its two corners at the same rate: the
/// toe of EKTACHROME E100 needs 5 and its shoulder 2, and holding both at 4
/// leaves a residual of 0.036 that two numbers take to 0.008. The amplitude of
/// each corner is `gamma` in both terms — which is what makes the plateau come
/// out at `gamma · (shoulder − toe)` whatever the two rates are, and is why
/// equal rates reproduce the one-transition curve exactly rather than nearly.
#[inline]
#[must_use]
pub fn density_from(
    d_min: f64,
    d_max: f64,
    gamma: f64,
    log_e0: f64,
    toe_transition: f64,
    shoulder_transition: f64,
    log_e: f64,
) -> f64 {
    let span = d_max - d_min;
    let gamma = gamma.max(1e-9);
    let half = 0.5 * span.abs() / gamma;
    let toe_slope = toe_transition.max(1e-3);
    let shoulder_slope = shoulder_transition.max(1e-3);
    // A negative's density rises with exposure and a reversal's falls. The curve
    // is the same shape either way — toe, straight line, shoulder — so the span
    // carries the direction and `gamma` stays the magnitude of the slope. See
    // the note on [`CharacteristicCurve::d_min`].
    let direction = if span < 0.0 { -1.0 } else { 1.0 };
    let toe = softplus(toe_slope * (log_e - (log_e0 - half))) / toe_slope;
    let shoulder = softplus(shoulder_slope * (log_e - (log_e0 + half))) / shoulder_slope;
    // The clamp is not defensive arithmetic, it is what makes the two-rate
    // shape a curve at all. A difference of two logistics with *different*
    // slopes is not monotone: far outside both corners the slower one wins, so
    // the travel goes a little the wrong side of its asymptote — 0.008 of a
    // density unit for this film's 5/2 pair, in a tail the sheet never drew.
    // Clamping to the span puts the plateaus back exactly where they are
    // supposed to be, and it costs nothing where the data is: with equal rates
    // the travel is inside [0, span] everywhere, so the clamp never binds and
    // the one-transition curve is reproduced exactly.
    let travel = (gamma * (toe - shoulder)).clamp(0.0, span.abs());
    d_min + direction * travel
}

/// The curve's local slope at a log exposure, in density per decade.
#[inline]
#[must_use]
pub fn slope_from(
    d_min: f64,
    d_max: f64,
    gamma: f64,
    log_e0: f64,
    toe_transition: f64,
    shoulder_transition: f64,
    log_e: f64,
) -> f64 {
    let span = d_max - d_min;
    let gamma = gamma.max(1e-9);
    let half = 0.5 * span.abs() / gamma;
    let toe_slope = toe_transition.max(1e-3);
    let shoulder_slope = shoulder_transition.max(1e-3);
    let direction = if span < 0.0 { -1.0 } else { 1.0 };
    // Where `density_from` clamps, the curve is flat, so the slope there is
    // zero rather than the sign of the tail being clamped away. The bound is on
    // the *travel*, which is what density_from clamps; the slope itself is not
    // bounded by the span and must not be compared with it.
    let travel = gamma
        * (softplus(toe_slope * (log_e - (log_e0 - half))) / toe_slope
            - softplus(shoulder_slope * (log_e - (log_e0 + half))) / shoulder_slope);
    if travel <= 0.0 || travel >= span.abs() {
        return 0.0;
    }
    direction
        * gamma
        * (sigmoid(toe_slope * (log_e - (log_e0 - half)))
            - sigmoid(shoulder_slope * (log_e - (log_e0 + half))))
}

/// A single characteristic curve.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CharacteristicCurve {
    /// Density of the unexposed, processed material (base + fog).
    ///
    /// For film this is zero: the curve describes how much dye has formed, and
    /// the base — fog and the orange mask — is carried separately. It is the
    /// exception that proves the rule: a **reversal** film starts at its
    /// maximum density on unexposed film and clears as the image forms, so its
    /// `d_min` is the density of the unexposed slide (about 3.4) and its
    /// `d_max` is the clear film (0). `d_min > d_max` is a reversal, and the
    /// curve shape is the same one turned over.
    pub d_min: f64,
    /// Density at full exposure (the shoulder), or zero for a reversal.
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
    /// How sharply the toe — the low-exposure corner — turns, per decade.
    ///
    /// [`TRANSITION`] unless a measurement said otherwise: the measured stocks
    /// carry their own, from 7 for a print to 10 for a harder-cornered one.
    pub toe_transition: f64,
    /// How sharply the shoulder turns, per decade.
    ///
    /// Equal to [`Self::toe_transition`] for every stock whose two corners were
    /// read as one number, which is all of them but EKTACHROME E100. See
    /// [`density_from`] for why the shape can carry two rates and still reach
    /// its plateaus.
    pub shoulder_transition: f64,
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
            toe_transition: TRANSITION,
            shoulder_transition: TRANSITION,
        }
    }

    /// The same curve, made of a material that turns both its corners alike.
    #[must_use]
    pub const fn with_transition(self, transition: f64) -> Self {
        Self {
            toe_transition: transition,
            shoulder_transition: transition,
            ..self
        }
    }

    /// The same curve, turned by a different amount at each corner.
    ///
    /// The two rates are independent, and a measured curve usually wants them to
    /// be: EKTACHROME E100's toe turns at 5 per decade and its shoulder at 2,
    /// and the fit is 0.008 with that pair against 0.036 at the 4/4 one that a
    /// single number forces.
    #[must_use]
    pub const fn with_corners(self, toe: f64, shoulder: f64) -> Self {
        Self {
            toe_transition: toe,
            shoulder_transition: shoulder,
            ..self
        }
    }

    /// Height of the curve, in density units, **signed**.
    ///
    /// Positive for a material that darkens with exposure — paper, a negative —
    /// and negative for a reversal, whose density starts at its maximum on
    /// unexposed film and falls as the image forms. The sign is what makes one
    /// curve shape serve both; [`Self::amplitude`] is its magnitude.
    #[must_use]
    pub fn span(&self) -> f64 {
        self.d_max - self.d_min
    }

    /// How far the curve travels, in density units, whichever way it goes.
    #[must_use]
    pub fn amplitude(&self) -> f64 {
        self.span().abs().max(1e-9)
    }

    /// Whether the density rises with exposure.
    #[must_use]
    pub fn rises(&self) -> bool {
        self.span() >= 0.0
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
            self.toe_transition,
            self.shoulder_transition,
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
            self.toe_transition,
            self.shoulder_transition,
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
        let span = self.span();
        let half = 0.5 * span.abs() / self.gamma.max(1e-9);
        let target = (density - self.d_min) / span;
        // A density at (or past) the ends of the curve is the asymptote of the
        // exposure axis, on whichever side the curve starts.
        let direction = if span < 0.0 { -1.0 } else { 1.0 };
        if target <= 1e-12 {
            return self.log_e0 - direction * (half + 10.0);
        }
        if target >= 1.0 - 1e-12 {
            return self.log_e0 + direction * (half + 10.0);
        }

        // A bracket wide enough to contain the answer for any sane curve, then
        // bisection: forty halvings is a factor of 10^12, far past f64.
        let mut low = self.log_e0 - half - 10.0;
        let mut high = self.log_e0 + half + 10.0;
        for _ in 0..200 {
            let middle = 0.5 * (low + high);
            let below = if direction > 0.0 {
                self.density(middle) < density
            } else {
                self.density(middle) > density
            };
            if below {
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

    /// A reversal film is the same curve turned over: density starts at its
    /// maximum on unexposed film and falls to clear as the image forms. The
    /// shape, the straight line and the corners are the negative's; only the
    /// direction of the span changes, so nothing about the model doubles.
    #[test]
    fn a_reversal_falls_instead_of_rising() {
        // A harder corner than a negative's default, so the straight line is
        // actually straight over its middle: the test is about the direction.
        let reversal = CharacteristicCurve::new(3.4, 0.0, 1.9, -0.4).with_transition(8.0);
        assert!(!reversal.rises());
        assert!((reversal.span() + 3.4).abs() < 1e-12);
        assert!((reversal.amplitude() - 3.4).abs() < 1e-12);

        let mut previous = f64::INFINITY;
        for i in -900..900 {
            let log_e = f64::from(i) / 100.0;
            let d = reversal.density(log_e);
            // Flat where the curve has flattened: the toe is a plateau and f64
            // gets there exactly, so the test allows equality there and demands
            // a fall everywhere the curve is still moving.
            assert!(d <= previous + 1e-12, "a reversal's density must not rise");
            assert!(
                (-1e-6..=3.4 + 1e-6).contains(&d),
                "escaped the curve at {d}"
            );
            previous = d;
        }
        assert!(reversal.density(-2.0) - reversal.density(2.0) > 2.5);

        // The straight line still has slope gamma, in the other direction.
        let middle = reversal.slope_at(reversal.log_e0);
        assert!(
            (middle + 1.9).abs() < 0.02 * 1.9,
            "centre slope {middle} vs -gamma"
        );

        // And the inverse still inverts, on both sides of the middle.
        for density in [3.2, 2.0, 1.0, 0.2] {
            let back = reversal.density(reversal.log_exposure_at(density));
            assert!((back - density).abs() < 1e-6, "{density} came back {back}");
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

    /// One corner rate is the old shape, exactly — not nearly.
    ///
    /// The two-transition curve is a generalisation of the one-transition curve,
    /// so a stock that carries `with_transition(4.0)` must be bit-comparable
    /// with what it rendered before the change. That is what this holds: the
    /// plateau identity is algebraic, so equal rates give equal densities.
    #[test]
    fn one_rate_is_the_old_curve() {
        for (d_min, d_max, gamma, log_e0, rate) in [
            (0.2, 2.2, 0.6, -0.75, 4.0),
            (3.35, 0.18, 2.22, -1.19, 6.0),
            (0.0964, 2.5358, 3.7821, -1.4125, 7.0),
        ] {
            let curve = CharacteristicCurve::new(d_min, d_max, gamma, log_e0).with_transition(rate);
            let span = d_max - d_min;
            let half = 0.5 * span.abs() / gamma;
            let direction = if span < 0.0 { -1.0 } else { 1.0 };
            for i in -40..=40 {
                let log_e = log_e0 + f64::from(i) / 8.0;
                // The shape before the second rate existed.
                let old = d_min
                    + direction
                        * (gamma / rate)
                        * (softplus(rate * (log_e - (log_e0 - half)))
                            - softplus(rate * (log_e - (log_e0 + half))));
                let new = curve.density(log_e);
                assert!((old - new).abs() < 1e-12, "{log_e}: {old} against {new}");
            }
        }
    }

    /// The two corners can turn at different rates without moving the plateaus.
    ///
    /// This is the property the shape was generalised to keep: the amplitudes of
    /// the two corner terms are both `gamma`, so the curve still arrives at
    /// `d_min + span` whatever the rates are, and the straight line in between
    /// still has slope `gamma`. A construction that let the plateau depend on
    /// the rates would fit a curve by moving its asymptotes, which is what the
    /// first attempt at this did and why it looked like it worked.
    #[test]
    fn two_rates_keep_the_plateaus_and_the_line() {
        let base = CharacteristicCurve::new(3.35, 0.18, 2.22, -1.19);
        for (toe, shoulder) in [(5.0, 2.0), (2.0, 5.0), (8.0, 1.5), (4.0, 4.0)] {
            let curve = base.with_corners(toe, shoulder);
            // The plateaus, read six decades outside the corners: a softplus
            // approaches its asymptote exponentially, so the rate decides how
            // far out "flat" is and the tolerance has to be stated with it.
            let high = curve.density(curve.log_e0 - 6.0);
            let low = curve.density(curve.log_e0 + 6.0);
            assert!(
                (high - 3.35).abs() < 1e-3,
                "{toe}/{shoulder}: unexposed at {high}"
            );
            assert!(
                (low - 0.18).abs() < 1e-3,
                "{toe}/{shoulder}: clear at {low}"
            );
            // The centre slope is *not* gamma once the rates differ, and that
            // is not a defect: `gamma` is the slope the trapezoid would have if
            // both corners were sharp, and a gentle corner reaches it only in
            // the limit. What must survive is monotonicity and the inverse.
            let mut steepest = 0.0_f64;
            let mut previous = f64::INFINITY;
            for i in -300..300 {
                let log_e = curve.log_e0 + f64::from(i) / 40.0;
                steepest = steepest.max(curve.slope_at(log_e).abs());
                let d = curve.density(log_e);
                assert!(d <= previous + 1e-12, "{toe}/{shoulder} rose at {log_e}");
                previous = d;
            }
            assert!(
                steepest > 0.5 * 2.22 && steepest < 1.5 * 2.22,
                "{toe}/{shoulder}: steepest slope {steepest} against gamma 2.22"
            );
            for density in [3.2, 2.2, 1.2, 0.3] {
                let back = curve.density(curve.log_exposure_at(density));
                assert!((back - density).abs() < 1e-6, "{density} came back {back}");
            }
        }
    }

    /// A second rate earns its place only if it changes the curve where the
    /// data is: the residuals of EKTACHROME E100's red curve halve.
    ///
    /// The numbers here are the fit's, not invented: 0.0368 at 4/4 and 0.0076 at
    /// 5/2, measured against the digitised points in the film's own directory.
    /// The test holds the *direction* and a margin, because a shape that cannot
    /// express this difference is the reason the change was made.
    #[test]
    fn a_different_toe_changes_the_middle_of_the_curve() {
        let at_four =
            CharacteristicCurve::new(3.3476, 0.1816, 2.2233, -1.1944).with_transition(4.0);
        let split = at_four.with_corners(5.0, 2.0);
        let mut moved = 0.0_f64;
        for i in 0..=80 {
            let log_e = at_four.log_e0 - 2.0 + 0.05 * f64::from(i);
            moved = moved.max((split.density(log_e) - at_four.density(log_e)).abs());
        }
        assert!(moved > 0.02, "the two shapes differ by only {moved}");
        // Both are still the same film: a fifth of the span apart at most, which
        // is 0.6 of density for this curve and comfortably more than the 0.39
        // the two measured shapes actually reach.
        assert!(moved < 0.6, "the two shapes differ by {moved}");
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
