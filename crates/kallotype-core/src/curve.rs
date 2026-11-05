//! The characteristic curve — density as a function of log10 exposure.
//!
//! This is the H&D curve measured by Hurter and Driffield in 1890, and the
//! object the whole project is named after. Phase 0 models it as a logistic
//! in log-exposure, which is monotonic, has a closed-form inverse, and maps
//! cleanly onto the vocabulary photographers already use: `d_min` is base +
//! fog, `d_max` is the shoulder, `gamma` is the maximum slope, `log_e0` is the
//! speed point.

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

/// A single characteristic curve.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CharacteristicCurve {
    /// Density of the unexposed, processed material (base + fog).
    pub d_min: f64,
    /// Density at full exposure (the shoulder).
    pub d_max: f64,
    /// Maximum slope of the curve, in density per decade of exposure.
    pub gamma: f64,
    /// log10 exposure at the inflection point (half-way up the curve).
    pub log_e0: f64,
}

impl CharacteristicCurve {
    /// Build a curve from its four photographic parameters.
    #[must_use]
    pub const fn new(d_min: f64, d_max: f64, gamma: f64, log_e0: f64) -> Self {
        Self {
            d_min,
            d_max,
            gamma,
            log_e0,
        }
    }

    /// Height of the curve, in density units.
    #[must_use]
    pub fn span(&self) -> f64 {
        (self.d_max - self.d_min).max(1e-9)
    }

    /// Slope factor such that the maximum slope of the logistic equals `gamma`.
    #[must_use]
    pub fn slope_factor(&self) -> f64 {
        4.0 * self.gamma / self.span()
    }

    /// Density at a given log10 exposure.
    #[must_use]
    pub fn density(&self, log_e: f64) -> f64 {
        self.d_min + self.span() * sigmoid(self.slope_factor() * (log_e - self.log_e0))
    }

    /// log10 exposure at which `density` is reached; the inverse of [`Self::density`].
    ///
    /// `d_min` and `d_max` are asymptotes, so densities at (or beyond) the ends
    /// of the curve are clamped rather than inverted.
    #[must_use]
    pub fn log_exposure_at(&self, density: f64) -> f64 {
        let t = (density - self.d_min) / self.span();
        self.log_e0 + logit(t) / self.slope_factor()
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
        for i in -80..80 {
            let d = c.density(f64::from(i) / 10.0);
            assert!(d > previous, "density must increase with exposure");
            assert!((c.d_min..=c.d_max).contains(&d));
            previous = d;
        }
    }

    #[test]
    fn maximum_slope_equals_gamma() {
        let c = curve();
        let h = 1e-4;
        let x = c.log_e0;
        let slope = (c.density(x + h) - c.density(x - h)) / (2.0 * h);
        assert!((slope - c.gamma).abs() < 1e-6, "slope {slope}");
    }

    #[test]
    fn inverse_agrees_with_forward() {
        let c = curve();
        // The ends are asymptotes, so only the interior is invertible.
        for i in 1..10 {
            let d = c.d_min + c.span() * f64::from(i) / 10.0;
            let x = c.log_exposure_at(d);
            assert!((c.density(x) - d).abs() < 1e-9);
        }
    }
}
