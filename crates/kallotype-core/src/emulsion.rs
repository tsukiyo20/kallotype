//! Built-in film and paper stocks.
//!
//! Two of them are measured — the film `vision3_500t` and the paper
//! `endura_premier_metallic`. Their curves are digitised from the manufacturer's
//! data sheets, and the film's spectra are the ones compiled into
//! `crate::measured`. Everything else is a stand-in with realistic numbers, and
//! the notes on each say which it is.
//!
//! The ids of the stand-ins deliberately name no real product. A stock called
//! `portra400` that is not Portra 400 would be a lie, and the whole point of this
//! project is that the numbers mean something. The measured one names its own
//! film, because it is that film.
//!
//! ## What `d_min` means, and why it is zero for film
//!
//! A colour negative's minimum density is **not part of its characteristic
//! curve**. It is base, fog and — the part that matters — the orange mask: a
//! coloured coupler that absorbs blue and is consumed where cyan dye forms. It
//! is spectrally structured, so the model carries it as a spectrum
//! (`crate::measured::FILM_MASK`), not as a scalar under the curve.
//!
//! The curve therefore describes how much *dye* has formed, which is zero where
//! nothing was exposed. [`FilmStock::base_density`] is the same minimum density
//! expressed the way the non-spectral print needs it: one status density per
//! layer. The two are not independent numbers — the mask's density at the status
//! filter peaks is this base, and a test checks it.
//!
//! Paper is the exception and keeps its `d_min`: unexposed paper has a density
//! of its own, it has no mask, and there is no second place to put it.

use crate::curve::CharacteristicCurve;
use crate::measured::{PAPER_DYES, PAPER_DYES_E4021, PAPER_LAYERS, PAPER_LAYERS_E4021};
use crate::spectral::GRID_LEN;

/// A film stock: one characteristic curve per colour layer.
#[derive(Debug, Clone, Copy)]
pub struct FilmStock {
    /// Stable identifier used on the command line.
    pub id: &'static str,
    /// Human-readable name.
    pub label: &'static str,
    /// What this stock is, and what it is not.
    pub note: &'static str,
    /// Red, green and blue layer curves, in dye formed: `d_min` is the fog above
    /// the base, and zero at a normal development.
    pub channels: [CharacteristicCurve; 3],
    /// Status densities of the unexposed, processed film: base, fog and mask.
    ///
    /// Used by the non-spectral print, which has no spectrum to put there. The
    /// spectral print uses the measured mask instead, and the two agree.
    pub base_density: [f64; 3],
    /// Effective developed grains per square micrometre, per layer.
    ///
    /// "Effective" is doing work in that sentence: a developed image's noise is
    /// dominated by clumping, so the number is far below a count of silver
    /// halide grains. It is whatever reproduces the manufacturer's granularity
    /// curve, and [`crate::GrainField::for_stock`] is where it goes.
    pub grains_per_um2: [f64; 3],
}

/// A paper stock: one curve, because paper only has to record what is on the
/// negative, not sample a scene.
#[derive(Debug, Clone, Copy)]
pub struct PaperStock {
    /// Stable identifier used on the command line.
    pub id: &'static str,
    /// Human-readable name.
    pub label: &'static str,
    /// What this paper is, and what it is not.
    pub note: &'static str,
    /// The paper's characteristic curve.
    pub channel: CharacteristicCurve,
    /// Linear reflectance a correctly balanced print should reach for an
    /// 18 % grey card. This is what the print balance is solved against.
    pub target_mid_reflectance: f64,
    /// The paper's cyan, magenta and yellow dyes, peak-normalised absorption,
    /// 380–730 nm at 5 nm. What the spectral scan puts between the light and
    /// the eye.
    pub dyes: &'static [[f64; GRID_LEN]; 3],
    /// The paper's three layer sensitivities on one relative scale, 380–730 nm
    /// at 5 nm. What the spectral print integrates the enlarger's light against.
    pub layers: &'static [[f64; GRID_LEN]; 3],
}

const fn curve(d_min: f64, d_max: f64, gamma: f64, log_e0: f64) -> CharacteristicCurve {
    CharacteristicCurve::new(d_min, d_max, gamma, log_e0)
}

/// Every film stock compiled into the binary.
pub static FILM_STOCKS: &[FilmStock] = &[
    FilmStock {
        id: "vision3_500t",
        label: "KODAK VISION3 500T 5219/7219, ECN-2",
        note: "Measured. Curves digitised from data sheet H-1-5219 page 3, spectra \
               from page 4; see the notes in kallotype-private for each extraction.",
        // Red, green and blue in that order. `d_max` is the span the data sheet's
        // curve covers above its own minimum density: 1.8685 − 0.1867 and so on.
        channels: [
            curve(0.0, 1.6818, 0.4745, -0.7582),
            curve(0.0, 1.9964, 0.5570, -0.7298),
            curve(0.0, 1.9196, 0.5454, -0.7462),
        ],
        // The plateaus of the same curves at −8 stops, which is the film's
        // minimum density in status terms.
        base_density: [0.1867, 0.5782, 0.8319],
        // Derived from the rms granularity chart on the same page: the inverse
        // of what it takes to reproduce sigma D = 0.0060 / 0.0077 / 0.0197 at a
        // density of 1 through a 48 µm aperture. Blue is the front layer and the
        // grainiest by a factor of nine.
        grains_per_um2: [0.62, 0.51, 0.07],
    },
    FilmStock {
        id: "c41_standard",
        label: "Colour negative, standard development",
        note: "Placeholder C-41 curve: moderate contrast, even layer speeds.",
        channels: [
            curve(0.0, 2.08, 0.60, -0.75),
            curve(0.0, 2.11, 0.63, -0.75),
            curve(0.0, 2.14, 0.66, -0.76),
        ],
        base_density: [0.22, 0.22, 0.22],
        grains_per_um2: [3.6, 3.6, 3.6],
    },
    FilmStock {
        id: "c41_contrast",
        label: "Colour negative, high-contrast",
        note: "Placeholder C-41 curve with a steeper shoulder and stronger layer separation.",
        channels: [
            curve(0.0, 2.25, 0.70, -0.72),
            curve(0.0, 2.28, 0.73, -0.73),
            curve(0.0, 2.31, 0.76, -0.74),
        ],
        base_density: [0.20, 0.20, 0.20],
        grains_per_um2: [3.6, 3.6, 3.6],
    },
    FilmStock {
        id: "bw_classic",
        label: "Black and white, classic",
        note: "Placeholder B&W curve: identical layers, longer straight line.",
        channels: [
            curve(0.0, 2.50, 0.58, -0.80),
            curve(0.0, 2.50, 0.58, -0.80),
            curve(0.0, 2.50, 0.58, -0.80),
        ],
        base_density: [0.10, 0.10, 0.10],
        grains_per_um2: [3.6, 3.6, 3.6],
    },
];

/// Every paper stock compiled into the binary.
pub static PAPER_STOCKS: &[PaperStock] = &[
    PaperStock {
        id: "portra_endura",
        label: "KODAK PROFESSIONAL PORTRA ENDURA, RA-4",
        note: "Measured. Curve from data sheet E-4021 page 7, the \
               normal-contrast professional paper; dyes and layer \
               sensitivities from page 8 of the same sheet. White 0.096 status \
               density, a print's, not the metallic stock's.",
        // The mean of the three measured layers at a transition of 7. Per layer
        // they are red (0.0909, 2.6087, 3.68, −1.4125), green (0.0929, 2.5928,
        // 3.38, −1.3950) and blue (0.1048, 2.4137, 4.57, −1.4275), reproduced to
        // an rms of 0.017, 0.024 and 0.015. This chart is drawn as straight
        // segments rather than cubics, which puts a floor of about 0.01 under
        // any fit — the model is at that floor, not above it.
        channel: curve(0.0964, 2.5358, 3.7821, -1.4125).with_transition(7.0),
        target_mid_reflectance: 0.18,
        dyes: &PAPER_DYES_E4021,
        layers: &PAPER_LAYERS_E4021,
    },
    PaperStock {
        id: "supra_endura",
        label: "KODAK PROFESSIONAL SUPRA ENDURA, RA-4",
        note: "Measured. Curve digitised from the same sheet and page as PORTRA \
               ENDURA: the higher-contrast professional paper. White 0.102.",
        // The mean of the three layers at a transition of 8; per layer red
        // (0.0943, 2.6607, 5.13, −1.1550), green (0.1048, 2.5631, 4.31, −1.1400)
        // and blue (0.1073, 2.5307, 5.16, −1.1750), rms 0.025, 0.024, 0.032.
        channel: curve(0.1010, 2.5847, 4.7309, -1.1575).with_transition(8.0),
        target_mid_reflectance: 0.18,
        // E-4021 draws one set of spectra for both its papers.
        dyes: &PAPER_DYES_E4021,
        layers: &PAPER_LAYERS_E4021,
    },
    PaperStock {
        id: "endura_premier_metallic",
        label: "KODAK PROFESSIONAL ENDURA Premier Metallic, RA-4",
        note: "Measured. Curve digitised from data sheet E-4071 page 4; its three \
               dye spectra come from page 5 of the same sheet. The white is the \
               metallic base's, 0.21 status density, not a normal paper's 0.07.",
        // The mean of the three measured layers, fitted at the paper's
        // transition of 10. Per layer they are red (0.2078, 2.7739, 5.24,
        // −1.175), green (0.2043, 2.5258, 5.40, −1.205) and blue (0.1707,
        // 2.4699, 6.66, −1.193), each reproduced to an rms of 0.013, 0.010 and
        // 0.007. One curve serves the print, so this one is their average and
        // the layer spread at the shoulder — 0.30 of density — is what that
        // single curve cannot say.
        channel: curve(0.1944, 2.5902, 5.5716, -1.1900).with_transition(10.0),
        target_mid_reflectance: 0.18,
        dyes: &PAPER_DYES,
        layers: &PAPER_LAYERS,
    },
    PaperStock {
        id: "c41_paper",
        label: "Colour paper, RA-4",
        note: "Placeholder RA-4 paper: low d_min, short contrasty curve.",
        channel: curve(0.06, 2.05, 2.40, 0.0),
        target_mid_reflectance: 0.18,
        // No measurement of its own: the metallic sheet's spectra stand in.
        dyes: &PAPER_DYES,
        layers: &PAPER_LAYERS,
    },
    PaperStock {
        id: "bw_paper",
        label: "Fibre-based B&W paper",
        note: "Placeholder B&W paper: deeper blacks, steeper curve.",
        channel: curve(0.05, 2.10, 2.80, 0.0),
        target_mid_reflectance: 0.18,
        dyes: &PAPER_DYES,
        layers: &PAPER_LAYERS,
    },
];

/// Look up a film stock by id.
#[must_use]
pub fn film_stock(id: &str) -> Option<&'static FilmStock> {
    FILM_STOCKS.iter().find(|stock| stock.id == id)
}

/// Look up a paper stock by id.
#[must_use]
pub fn paper_stock(id: &str) -> Option<&'static PaperStock> {
    PAPER_STOCKS.iter().find(|stock| stock.id == id)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::grain::GrainField;

    /// The measured stock's status base and the mask the spectral print adds are
    /// one measurement written two ways. If they ever drift apart, one of the two
    /// prints is wrong and the difference is a colour cast in the shadows.
    #[test]
    fn the_measured_stock_carries_the_mask_as_its_base() {
        let stock = film_stock("vision3_500t").expect("the measured stock");
        let mask = crate::measured::spectrum(&crate::measured::FILM_MASK);
        for (channel, wavelength) in [650.0, 550.0, 450.0].iter().enumerate() {
            let at = mask.interpolate(*wavelength);
            assert!(
                (stock.base_density[channel] - at).abs() < 0.06,
                "layer {channel}: base {:.4} against mask {at:.4}",
                stock.base_density[channel]
            );
        }
    }

    /// The granularity chart gives a *density* fluctuation; the model works in
    /// log exposure, and the curve's slope connects them. This is the round trip
    /// through the whole derivation: at a density of 1 through a 48 µm aperture,
    /// rms granularity has to land where the data sheet put it.
    #[test]
    fn the_measured_grain_reproduces_the_granularity_chart() {
        let stock = film_stock("vision3_500t").expect("the measured stock");
        let mut field = GrainField::for_stock(1, 1, 36.0, 0, stock);
        field.pixel_area_um2 = 48.0 * 48.0;
        // The chart's values at D = 1, in layer order R, G, B.
        for (layer, published) in [0.0060, 0.0077, 0.0197].into_iter().enumerate() {
            let sigma_d = stock.channels[layer].gamma * field.sigma(1.0, layer);
            assert!(
                (sigma_d - published).abs() < 0.2 * published,
                "layer {layer}: {sigma_d:.4} against the chart's {published:.4}"
            );
        }
    }

    /// A film curve is dye, and dye is zero where nothing was exposed. The base
    /// lives on the stock so that a spectral print can put the measured mask
    /// there instead of a scalar.
    #[test]
    fn film_curves_start_at_zero_density() {
        for stock in FILM_STOCKS {
            for (layer, channel) in stock.channels.iter().enumerate() {
                assert!(
                    channel.d_min.abs() < 1e-9,
                    "{} layer {layer}: d_min {}",
                    stock.id,
                    channel.d_min
                );
            }
        }
    }

    /// Paper keeps its `d_min`, unlike film: unexposed paper has a density of
    /// its own and no mask to carry it. That `d_min` is the paper's white, and
    /// the three measured stocks have three different ones — 0.19 for the
    /// metallic sheet, 0.10 for the two E-4021 papers. The default is one of
    /// the latter, because a model whose prints cannot reflect more than 62 %
    /// is modelling a specialty, not a print.
    #[test]
    fn the_measured_papers_carry_their_white_as_the_toe() {
        let measured = [
            ("portra_endura", 0.0964, 7.0),
            ("supra_endura", 0.1010, 8.0),
            ("endura_premier_metallic", 0.1944, 10.0),
        ];
        for (id, toe, transition) in measured {
            let paper = paper_stock(id).unwrap_or_else(|| panic!("{id} is not a stock"));
            assert!(
                (paper.channel.d_min - toe).abs() < 1e-9,
                "{id}: d_min {} is not the measured toe {toe}",
                paper.channel.d_min
            );
            assert!(
                (paper.channel.transition - transition).abs() < 1e-9,
                "{id}: transition {}, not the {transition} its sheet fitted",
                paper.channel.transition
            );
        }

        // The default paper is a print: its white is around 80 % reflectance,
        // where the metallic stock's is around 62 %.
        let default = paper_stock("portra_endura").expect("the default paper");
        let white = 10.0_f64.powf(-default.channel.d_min);
        assert!(
            (0.7..0.9).contains(&white),
            "the default paper's white came out at {white}"
        );
        assert!(
            10.0_f64.powf(
                -paper_stock("endura_premier_metallic")
                    .unwrap()
                    .channel
                    .d_min
            ) < 0.7,
            "the metallic paper is not greyer than a print"
        );
    }

    /// The paper's spectra belong to the stock, not to the model: E-4021 draws
    /// one set for PORTRA and SUPRA ENDURA, the metallic sheet another, and the
    /// E-4021 paper is the default. If a stock were pointed at the wrong tables
    /// nothing would fail except a spectral render's colour — which is exactly
    /// the failure mode this project exists to make loud.
    #[test]
    fn the_measured_papers_carry_their_own_spectra() {
        let peak = |table: &[f64; crate::spectral::GRID_LEN]| {
            let (index, value) =
                table
                    .iter()
                    .enumerate()
                    .fold((0, f64::NEG_INFINITY), |best, (i, &v)| {
                        if v > best.1 { (i, v) } else { best }
                    });
            (380.0 + 5.0 * index as f64, value)
        };

        let portra = paper_stock("portra_endura").expect("the default paper");
        // The dye peaks the sheet draws: yellow 445, magenta 550, cyan 630 nm.
        for (layer, expected) in [(2, 445.0), (1, 550.0), (0, 630.0)] {
            let (wavelength, value) = peak(&portra.dyes[layer]);
            assert!(
                (wavelength - expected).abs() < 15.0,
                "layer {layer} peaks at {wavelength} nm, not {expected}"
            );
            assert!((value - 1.0).abs() < 0.02, "layer {layer} peaks at {value}");
        }
        // The layer sensitivities: yellow-forming at 475, magenta at 550, cyan
        // at 705, and they are on one scale, so their peaks differ by two orders.
        let yellow = peak(&portra.layers[2]).1;
        let cyan = peak(&portra.layers[0]).1;
        assert!(
            yellow > 20.0 * cyan,
            "the layer speeds came out {yellow:.2} and {cyan:.2}"
        );

        // And the metallic stock is a different paper, with different tables.
        let metallic = paper_stock("endura_premier_metallic").expect("the metallic paper");
        assert!(
            !std::ptr::eq(portra.dyes, metallic.dyes),
            "the two papers share one dye set"
        );
        assert!((peak(&metallic.dyes[0]).0 - peak(&portra.dyes[0]).0).abs() > 5.0);
    }

    #[test]
    fn ids_are_unique() {
        let mut ids: Vec<&str> = FILM_STOCKS.iter().map(|s| s.id).collect();
        ids.sort_unstable();
        let count = ids.len();
        ids.dedup();
        assert_eq!(ids.len(), count);

        let mut ids: Vec<&str> = PAPER_STOCKS.iter().map(|s| s.id).collect();
        ids.sort_unstable();
        let count = ids.len();
        ids.dedup();
        assert_eq!(ids.len(), count);
    }

    #[test]
    fn lookups_work() {
        assert!(film_stock("c41_standard").is_some());
        assert!(paper_stock("c41_paper").is_some());
        assert!(film_stock("nope").is_none());
    }
}
