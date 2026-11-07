//! The measured spectral sensitivity of the film's three layers.
//!
//! Until this module existed the layers were three Gaussians: a guess about
//! where a film responds, not a statement about any film. These are the curves
//! from the technical data sheet for KODAK VISION3 500T 5219/7219 (publication
//! H-1-5219, page 4), digitised from the chart and resampled to 5 nm.
//!
//! The chart plots *log* sensitivity: the reciprocal exposure, in erg/cm²,
//! needed to reach a fixed density under monochromatic light. Up to a constant
//! that is the layer's spectral response, so the table is `10^log`.
//!
//! The three curves were measured on one scale, so they are divided by a single
//! constant — the largest sample in the table — instead of being normalised
//! channel by channel. That keeps the layers' relative sensitivity, which
//! survives the grey anchor and is part of what the film actually is.
//!
//! Order is R, G, B: the cyan-forming layer is the red-sensitive one, the
//! magenta-forming layer the green-sensitive one, and the yellow-forming layer
//! the blue-sensitive one. [`Sensor`](crate::Sensor) reads that order
//! everywhere, so getting it wrong stays invisible until a red patch comes out
//! blue.
//!
//! The table is embedded rather than loaded because the render path does no file
//! I/O; the CSV is the source of record and this is a copy of it.

/// Wavelength of the first sample, in nanometres.
pub(crate) const START_NM: f64 = 380.0;
/// Wavelength step between samples, in nanometres.
pub(crate) const STEP_NM: f64 = 5.0;
/// Number of samples in each table.
pub(crate) const LEN: usize = 71;

/// The red-sensitive layer, which forms the cyan dye.
const CYAN: [f64; LEN] = [
    0.41337, 0.41337, 0.41337, 0.41337, 0.41337, 0.45028, 0.50055, 0.55642, 0.61854, 0.68758,
    0.76434, 0.84966, 0.94450, 1.04994, 1.16714, 1.29742, 1.44225, 1.60324, 1.78221, 1.98115,
    2.20231, 2.44814, 2.72142, 3.02521, 3.36291, 3.73830, 4.15898, 4.61045, 5.15297, 5.52980,
    5.50300, 5.17708, 4.68839, 4.19798, 4.36849, 5.71779, 8.18171, 10.98987, 14.31874, 21.31303,
    34.07942, 58.77370, 89.14844, 119.92908, 139.60969, 162.10765, 188.54216, 227.47778, 262.13894,
    256.75207, 241.33854, 236.78472, 241.24661, 263.91766, 284.29850, 283.19044, 251.95541,
    182.77781, 120.82338, 77.10338, 53.19030, 36.59458, 24.55757, 16.47988, 11.05918, 7.42150,
    4.98035, 3.34217, 2.24284, 1.50510, 1.01003,
];

/// The green-sensitive layer, which forms the magenta dye.
const MAGENTA: [f64; LEN] = [
    2.68677, 2.97456, 3.29317, 3.64591, 4.03643, 4.46879, 4.94745, 5.47738, 6.06407, 6.71361,
    7.43272, 8.22886, 9.11027, 10.08609, 11.16643, 12.31588, 13.78348, 15.04435, 17.77814,
    25.04719, 39.41081, 63.70564, 92.25824, 136.74944, 167.25197, 201.04280, 227.15302, 256.65427,
    284.89484, 327.64872, 373.60228, 438.68318, 510.02385, 576.26265, 607.94968, 568.68364,
    508.08443, 449.68241, 397.08469, 342.32325, 249.70967, 134.77107, 56.20067, 17.61632, 8.41726,
    3.53718, 1.48643, 1.14537, 1.14537, 1.14537, 1.14537, 1.14537, 1.14537, 1.14537, 1.14537,
    1.14537, 1.14537, 1.14537, 1.14537, 1.14537, 1.14537, 1.14537, 1.14537, 1.14537, 1.14537,
    1.14537, 1.14537, 1.14537, 1.14537, 1.14537, 1.14537,
];

/// The blue-sensitive layer, which forms the yellow dye.
const YELLOW: [f64; LEN] = [
    696.65803, 899.58754, 1139.49252, 1350.28049, 1530.74115, 1590.94293, 1560.92341, 1531.47032,
    1502.57298, 1474.22090, 1446.40380, 1390.08172, 1314.99623, 1242.07221, 1184.94645, 1172.96878,
    1150.83601, 1172.96878, 1117.99142, 916.53907, 733.42680, 568.30461, 417.72392, 296.07114,
    200.43097, 128.25871, 77.04465, 46.20123, 25.08778, 12.09270, 5.52191, 2.62404, 1.24591,
    0.59157, 0.55009, 0.55009, 0.55009, 0.55009, 0.55009, 0.55009, 0.55009, 0.55009, 0.55009,
    0.55009, 0.55009, 0.55009, 0.55009, 0.55009, 0.55009, 0.55009, 0.55009, 0.55009, 0.55009,
    0.55009, 0.55009, 0.55009, 0.55009, 0.55009, 0.55009, 0.55009, 0.55009, 0.55009, 0.55009,
    0.55009, 0.55009, 0.55009, 0.55009, 0.55009, 0.55009, 0.55009, 0.55009,
];

/// The three tables, in the order the rest of the crate reads them: cyan,
/// magenta, yellow — that is, red-, green- and blue-sensitive.
pub const CHANNELS: [[f64; LEN]; 3] = [CYAN, MAGENTA, YELLOW];

#[cfg(test)]
mod tests {
    use super::*;

    fn peak(table: &[f64; LEN]) -> (f64, f64) {
        let index = table
            .iter()
            .enumerate()
            .max_by(|a, b| a.1.partial_cmp(b.1).expect("the table has no NaN"))
            .expect("the table is not empty")
            .0;
        (START_NM + STEP_NM * index as f64, table[index])
    }

    /// The data sheet draws the yellow-forming layer highest, the magenta-forming
    /// layer next and the cyan-forming layer lowest. This is the structural fact
    /// that survives a transcription error in any single channel.
    #[test]
    fn the_layers_peak_where_the_data_sheet_draws_them() {
        let cyan = peak(&CYAN);
        let magenta = peak(&MAGENTA);
        let yellow = peak(&YELLOW);
        assert!(
            (cyan.0 - 650.0).abs() <= 5.0,
            "red-sensitive layer peaks at {} nm",
            cyan.0
        );
        assert!(
            (magenta.0 - 550.0).abs() <= 5.0,
            "green-sensitive layer peaks at {} nm",
            magenta.0
        );
        assert!(
            (yellow.0 - 405.0).abs() <= 5.0,
            "blue-sensitive layer peaks at {} nm",
            yellow.0
        );
        assert!(
            yellow.1 > magenta.1 && magenta.1 > cyan.1,
            "peak heights {:.2} / {:.2} / {:.2}",
            yellow.1,
            magenta.1,
            cyan.1
        );
    }

    /// A layer that responds across the whole visible range is the signature of a
    /// table read off the wrong axis, not of a film. At each peak the other two
    /// layers are hundreds of times less sensitive, which is what makes a colour
    /// negative able to record three channels at all.
    #[test]
    fn the_layers_are_deaf_where_their_neighbours_peak() {
        let at = |table: &[f64; LEN], wavelength: f64| {
            table[((wavelength - START_NM) / STEP_NM).round() as usize]
        };
        let pairs = [
            (
                "blue at 405, red",
                at(&YELLOW, 405.0),
                at(&CYAN, 405.0),
                1000.0,
            ),
            (
                "red at 650, blue",
                at(&CYAN, 650.0),
                at(&YELLOW, 650.0),
                300.0,
            ),
            (
                "green at 550, red",
                at(&MAGENTA, 550.0),
                at(&CYAN, 550.0),
                100.0,
            ),
            (
                "green at 550, blue",
                at(&MAGENTA, 550.0),
                at(&YELLOW, 550.0),
                500.0,
            ),
        ];
        for (what, sensitive, deaf, minimum) in pairs {
            assert!(
                sensitive > minimum * deaf,
                "{what}: {sensitive:.4} is not {minimum} times {deaf:.4}"
            );
        }
    }
}
