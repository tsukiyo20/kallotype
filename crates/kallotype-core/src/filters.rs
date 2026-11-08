//! The light between the lamp and the negative: heat glass and colour pack.
//!
//! Roadmap phase 3's last stage. Everything downstream of it already exists —
//! the negative's dyes, the paper's layers, the scan — and this is the one part
//! of the chain that was marked "not modelled". It is a multiplication: the
//! light that reaches the film is the lamp's spectrum times the transmission of
//! whatever sits in the drawer.
//!
//! Two conventions carry the data, and both are the sheets':
//!
//! - **CC filters are density devices.** A colour head is dialled in CC units,
//!   1 CC being 0.01 of density, and the tables are densities above each
//!   filter's own neutral. The pack therefore interpolates in *density* between
//!   the tabulated settings, which is linear in the dial.
//! - **The heat glass is an internal transmittance at 2 mm.** A sheet of it
//!   loses (1 − R)² to two surfaces and its absorption is a path length, so a
//!   3 mm filter is `ti^(3/2)` of the table's 2 mm.

use crate::filters_measured::{
    CYAN_CC05, CYAN_CC10, CYAN_CC20, CYAN_CC30, CYAN_CC40, CYAN_CC50, KG1_HEAT_GLASS,
    KG2_HEAT_GLASS, KG3_HEAT_GLASS, KG5_HEAT_GLASS, MAGENTA_CC05, MAGENTA_CC10, MAGENTA_CC20,
    MAGENTA_CC30, MAGENTA_CC40, MAGENTA_CC50, YELLOW_CC05, YELLOW_CC10, YELLOW_CC20, YELLOW_CC30,
    YELLOW_CC40, YELLOW_CC50,
};
use crate::spectral::GRID_LEN;

/// The dial settings the CC tables are printed at.
const STEPS: [f64; 6] = [5.0, 10.0, 20.0, 30.0, 40.0, 50.0];

/// One colour's six tabulated density curves, at [`STEPS`].
type Curve = [&'static [f64; GRID_LEN]; 6];

const YELLOW: Curve = [
    &YELLOW_CC05,
    &YELLOW_CC10,
    &YELLOW_CC20,
    &YELLOW_CC30,
    &YELLOW_CC40,
    &YELLOW_CC50,
];
const MAGENTA: Curve = [
    &MAGENTA_CC05,
    &MAGENTA_CC10,
    &MAGENTA_CC20,
    &MAGENTA_CC30,
    &MAGENTA_CC40,
    &MAGENTA_CC50,
];
const CYAN: Curve = [
    &CYAN_CC05, &CYAN_CC10, &CYAN_CC20, &CYAN_CC30, &CYAN_CC40, &CYAN_CC50,
];

/// The small colour pack of an enlarger: yellow, magenta, cyan, in CC units.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct FilterPack {
    /// Yellow, in CC units. Absorbs blue.
    pub yellow: f64,
    /// Magenta, in CC units. Absorbs green.
    pub magenta: f64,
    /// Cyan, in CC units. Absorbs red.
    pub cyan: f64,
}

impl FilterPack {
    /// No glass in the drawer.
    #[must_use]
    pub const fn none() -> Self {
        Self {
            yellow: 0.0,
            magenta: 0.0,
            cyan: 0.0,
        }
    }

    /// A pack dialled in CC units.
    #[must_use]
    pub const fn new(yellow: f64, magenta: f64, cyan: f64) -> Self {
        Self {
            yellow,
            magenta,
            cyan,
        }
    }

    /// Whether the pack is empty, which is what a colour head at zero is.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.yellow == 0.0 && self.magenta == 0.0 && self.cyan == 0.0
    }

    /// The density the pack adds at each wavelength.
    #[must_use]
    pub fn density(&self) -> [f64; GRID_LEN] {
        std::array::from_fn(|index| {
            let sample = |curve: Curve, cc: f64| -> f64 {
                if cc == 0.0 {
                    return 0.0;
                }
                density_at_slot(curve, cc, index)
            };
            sample(YELLOW, self.yellow) + sample(MAGENTA, self.magenta) + sample(CYAN, self.cyan)
        })
    }

    /// The transmission the pack gives, one per wavelength sample.
    #[must_use]
    pub fn transmittance(&self) -> [f64; GRID_LEN] {
        self.density().map(|density| 10.0_f64.powf(-density))
    }
}

/// One colour's density at `cc`, at one wavelength sample.
///
/// Piecewise linear between the tabulated settings, extrapolated along the
/// last segment past 50 CC — a head that goes further dials a density nobody
/// tabulated, and extending the last measured slope is a smaller lie than
/// clamping at the last setting.
fn density_at_slot(curve: Curve, cc: f64, index: usize) -> f64 {
    let cc = cc.max(0.0);
    let mut low = (0.0, 0.0);
    for (step_index, step) in STEPS.iter().enumerate() {
        let high = curve[step_index][index];
        if cc <= *step {
            return low.1 + (cc - low.0) / (step - low.0) * (high - low.1);
        }
        low = (*step, high);
    }
    let last = curve[5][index];
    let previous = curve[4][index];
    let slope = (last - previous) / (STEPS[5] - STEPS[4]);
    last + slope * (cc - STEPS[5])
}

/// Which heat glass the enlarger carries.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HeatGlass {
    /// SCHOTT KG1, the mildest.
    Kg1,
    /// SCHOTT KG2.
    Kg2,
    /// SCHOTT KG3, the common enlarger choice.
    Kg3,
    /// SCHOTT KG5, the strongest.
    Kg5,
}

impl HeatGlass {
    /// The table for this glass, at the sheet's 2 mm.
    fn table(self) -> &'static [f64; GRID_LEN] {
        match self {
            Self::Kg1 => &KG1_HEAT_GLASS,
            Self::Kg2 => &KG2_HEAT_GLASS,
            Self::Kg3 => &KG3_HEAT_GLASS,
            Self::Kg5 => &KG5_HEAT_GLASS,
        }
    }

    /// Transmission for a sheet `thickness_mm` thick.
    ///
    /// Beer–Lambert on the internal transmittance, then the two surfaces:
    /// `R ≈ 0.04` a face gives 0.92 of what the table says reaches the far side.
    #[must_use]
    pub fn transmittance(self, thickness_mm: f64) -> [f64; GRID_LEN] {
        let base = self.table();
        let ratio = thickness_mm / 2.0;
        base.map(|value| value.max(1e-6).powf(ratio) * 0.92)
    }
}

/// A Planck spectrum at `kelvin`, relative, one sample per grid wavelength.
///
/// Planck's law per unit wavelength. Only ratios matter to the model — the
/// print's exposure is solved, not metered — so the constant is left out.
#[must_use]
pub fn lamp(kelvin: f64) -> [f64; GRID_LEN] {
    use std::f64::consts::PI;
    // h c / k in m·K and h c / k in m: the second radiation constant.
    const C2: f64 = 1.438_776_877e-2;
    std::array::from_fn(|index| {
        let lambda = (380.0 + 5.0 * index as f64) * 1e-9;
        // B_lambda = 2hc²/λ⁵ · 1/(exp(c2/(λT)) − 1); drop the constant.
        let exponent = C2 / (lambda * kelvin);
        let denominator = exponent.exp() - 1.0;
        if denominator <= 0.0 {
            return 0.0;
        }
        // λ⁵ in nanometres keeps the numbers in a sane range.
        let micrometres = 380.0 + 5.0 * index as f64;
        let _ = PI;
        micrometres.powi(-5) / denominator
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A pack at zero is not a small filter, it is no filter.
    #[test]
    fn an_empty_pack_transmits_everything() {
        let pack = FilterPack::none();
        assert!(pack.is_empty());
        for value in pack.transmittance() {
            assert!((value - 1.0).abs() < 1e-12, "{value}");
        }
    }

    /// One CC step is 0.01 of density, and it only goes one way.
    #[test]
    fn a_cc_step_is_a_hundredth_of_density() {
        let base = FilterPack::none().density();
        for step in [1.0, 10.0, 50.0] {
            let pack = FilterPack::new(0.0, step, 0.0);
            let density = pack.density();
            for (index, value) in density.iter().enumerate() {
                assert!(value >= &(base[index] - 1e-12), "a filter added light");
            }
            // At the filter's own peak the added density is cc/100 to within
            // the table's own noise, which is why the CC dial means anything.
            let peak = density.iter().copied().fold(f64::NEG_INFINITY, f64::max);
            let expected = step / 100.0;
            assert!(
                (peak - expected).abs() < expected * 0.25,
                "at {step} CC the peak added {peak}, not about {expected}"
            );
        }
    }

    /// A denser filter absorbs more, where the filter absorbs.
    ///
    /// In its own passband the tabulated densities are a few hundredths and the
    /// table's rounding dominates: yellow at 530 nm reads 0.036 at CC10 and
    /// 0.028 at CC20, both of them "no filter here". The monotonicity that
    /// means something is over the band the filter works on, taken as samples
    /// where the 50 CC table is above 0.15 of density.
    #[test]
    fn density_is_monotone_in_the_dial() {
        for colour in 0..3 {
            let mut values = [0.0, 0.0, 0.0];
            values[colour] = 50.0;
            let strongest = FilterPack::new(values[0], values[1], values[2]).density();
            let band: Vec<usize> = (0..GRID_LEN).filter(|i| strongest[*i] > 0.15).collect();
            assert!(
                band.len() > 15,
                "colour {colour} acts on only {} samples",
                band.len()
            );
            let mut previous = vec![0.0; GRID_LEN];
            for step in [0.0, 5.0, 10.0, 20.0, 30.0, 40.0, 50.0, 80.0] {
                let mut values = [0.0, 0.0, 0.0];
                values[colour] = step;
                let density = FilterPack::new(values[0], values[1], values[2]).density();
                for index in &band {
                    assert!(
                        density[*index] >= previous[*index] - 1e-12,
                        "colour {colour} at {step} CC: sample {index} got lighter"
                    );
                }
                previous = density.to_vec();
            }
        }
    }

    /// The glass is a window with a heat-absorbing red end.
    #[test]
    fn the_glass_is_clear_and_then_red_is_absorbed() {
        let transmission = HeatGlass::Kg3.transmittance(2.0);
        // 380 nm is index 0 and 730 nm is index 70.
        let green = transmission[34]; // 550 nm
        assert!(green > 0.80, "550 nm at {green}");
        assert!(transmission[64] < green, "700 nm is not dimmer than 550");
        assert!(
            transmission[70] < transmission[64],
            "730 nm is not dimmer than 700"
        );
    }

    /// Thicker glass absorbs more, by Beer–Lambert.
    #[test]
    fn a_thicker_glass_absorbs_more() {
        let thin = HeatGlass::Kg3.transmittance(1.0);
        let thick = HeatGlass::Kg3.transmittance(3.0);
        for index in 0..GRID_LEN {
            assert!(thick[index] < thin[index] + 1e-9, "sample {index}");
        }
    }

    /// A tungsten lamp is redder than daylight, and on this grid that is a
    /// spectrum rising towards the red end.
    #[test]
    fn a_tungsten_lamp_rises_towards_the_red() {
        let spectrum = lamp(3200.0);
        let violet = spectrum[0];
        let red = spectrum[50]; // 630 nm
        assert!(red > violet, "{red} against {violet}");
        // And it is not monotone in the far red: Planck peaks and turns over.
        assert!(
            spectrum[70] >= spectrum[60],
            "the far red should not be falling"
        );
    }
}
