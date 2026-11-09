//! Built-in film and paper stocks.
//!
//! Two of them are measured — the film `vision3_500t` and the paper
//! `endura_premier_metallic`. Their curves are digitised from the manufacturer's
//! data sheets. Everything else is a stand-in with realistic numbers, and the
//! notes on each say which it is.
//!
//! ## A stock carries its own spectra
//!
//! A film stock is not only a curve. It is also which wavelengths each layer
//! records ([`FilmStock::layers`]), what the negative absorbs at print time
//! ([`FilmStock::dyes`]) and the mask between the two ([`FilmStock::mask`]).
//! Those three are what make two films with the same contrast look like
//! different products, and they ride on the stock so that choosing a film
//! changes the colour and not only the density.
//!
//! The placeholder stocks borrow the measured VISION3 spectra and say so in
//! their notes. That is the honest version of a placeholder: the curve is
//! invented, and the colour response is somebody else's.
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
//! ([`FilmStock::mask`]), not as a scalar under the curve.
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
use crate::spectral::GRID_LEN;

/// Which chemistry the stock is, and therefore which stages the render runs.
///
/// A negative is developed, printed onto paper and scanned; a reversal is
/// developed to a positive and scanned directly, with no print between; a silver
/// image has one curve and one sensitivity, no dye and no mask. The stock
/// declares which one it is, and the pipeline follows.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FilmProcess {
    /// Colour negative: developed, printed onto paper, scanned.
    Negative,
    /// Colour reversal: the film is the picture, and there is no print stage.
    Reversal,
    /// Silver image: one curve, one sensitivity, no dye, no mask.
    Monochrome,
}
/// A film stock: one characteristic curve per colour layer.
#[derive(Debug, Clone, Copy)]

pub struct FilmStock {
    /// Stable identifier used on the command line.
    pub id: &'static str,
    /// The chemistry, and therefore which stages the render runs.
    pub process: FilmProcess,
    /// A second emulsion feeding the cyan dye, if the film has one.
    ///
    /// ADR 0017: a dye may be formed by more than one emulsion, and the
    /// four-layer negatives are the reason. `None` — every stock before those —
    /// is exactly the three-layer model.
    ///
    /// `Some` is not a scalar rendering: it forces the spectral path, because a
    /// fourth layer is a fourth integral, and it makes the GPU decline rather
    /// than replay three layers of a four-layer film.
    pub extra_cyan: Option<crate::dye::Emulsion>,
    /// A cyan-sensitive layer that releases inhibitor instead of dye, if the
    /// film has one — ADR 0018.
    ///
    /// It is not a dye: it forms no density, and its effect on the measured
    /// curve is folded into that curve. Only a frame with structure in it can
    /// show the layer at all, which is why nothing happens unless a render asks
    /// for [`crate::interimage::InterImage`].
    pub cl_layer: Option<crate::dye::InhibitorLayer>,
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
    /// The layer sensitivities on one relative scale, 380–730 nm at 5 nm.
    ///
    /// Which wavelengths reach each layer, and how fast each layer is. This is
    /// the film's *record* of colour: two stocks with the same curves but
    /// different layers separate a scene differently.
    pub layers: &'static [[f64; GRID_LEN]; 3],
    /// The cyan, magenta and yellow dyes, peak-normalised absorption.
    ///
    /// The film's *return* of colour: what the negative passes at print time.
    /// The published curves have D-min subtracted, so the mask is separate.
    pub dyes: &'static [[f64; GRID_LEN]; 3],
    /// Spectral density of base, fog and the orange mask, 380–730 nm at 5 nm.
    pub mask: &'static [f64; GRID_LEN],
    /// The emulsion's blur, measured from the stock's own MTF, per layer.
    ///
    /// `None` means the sheet did not publish a modulation-transfer curve and
    /// the render falls back to the compiled VISION3 fit — a borrow, and the
    /// stock's `note` says so.
    pub sigma_um: Option<[f64; 3]>,
    /// The development the characteristic curve was measured at, in minutes.
    ///
    /// Every sheet draws its curves at a stated development, and the model's
    /// default is not it: DELTA 400's curve is 8 minutes at 24 °C, most C-41
    /// sheets are 3¼ at 38 °C, and the model's own default is 6.5 at 20 °C.
    /// Rendering a stock at a development it was not measured at is a contrast
    /// factor the user did not ask for, so the reference rides on the stock and
    /// `--dev` is what moves away from it.
    pub reference_time_min: f64,
    /// The temperature the curve was measured at, in °C.
    pub reference_temp_c: f64,
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

// The film stocks are generated from the `.kalofilm` files at build time: the
// data is CC BY-SA 4.0 and this program text is MIT or Apache-2.0, and `build.rs` is
// where the two meet. Nothing in this file is a digitised number.
include!(concat!(env!("OUT_DIR"), "/film_stocks.rs"));

// The paper stocks are generated from the `.kalopaper` files the same way the
// films are; see `build.rs`.

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

    /// The second film is not the first one with another curve.
    ///
    /// Its layer sensitivities were digitised from its own data sheet, and its
    /// curves turn their corners at rates of their own. A stock that borrowed
    /// the first film's tables would render the same colour with a different
    /// contrast, which is the thing this field exists to prevent.
    #[test]
    fn the_second_film_has_its_own_layers() {
        let fuji = film_stock("fuji_nph400").expect("built-in stock");
        let kodak = film_stock("vision3_500t").expect("built-in stock");
        assert_ne!(
            (
                fuji.channels[0].toe_transition,
                fuji.channels[0].shoulder_transition
            ),
            (
                kodak.channels[0].toe_transition,
                kodak.channels[0].shoulder_transition
            ),
            "the two films fit the same corner rates"
        );
        let peak = |table: &[f64; GRID_LEN]| table.iter().copied().fold(0.0_f64, f64::max);
        let ratios: [f64; 3] =
            std::array::from_fn(|layer| peak(&fuji.layers[layer]) / peak(&kodak.layers[layer]));
        assert!(
            ratios.iter().any(|ratio| (ratio - 1.0).abs() > 0.05),
            "the two films share their layer tables: {ratios:?}"
        );
    }

    /// Every film carries three dyes, three layer sensitivities and a mask, on
    /// the grid the model integrates over, and none of them is negative.
    ///
    /// This is the check that catches a table pasted in at the wrong length or
    /// with a minus dropped: a stock with a truncated spectrum still renders,
    /// and it renders the wrong colour in a way nothing else would notice.
    #[test]
    fn every_film_carries_its_own_three_spectra() {
        for stock in FILM_STOCKS {
            // A silver film has no dyes; its record is the grain, and a table of
            // zeros is what "no dye absorption" looks like.
            if stock.process == FilmProcess::Monochrome {
                continue;
            }
            for (channel, table) in stock.dyes.iter().enumerate() {
                let peak = table.iter().copied().fold(0.0_f64, f64::max);
                assert!(
                    (peak - 1.0).abs() < 0.02,
                    "{} dye {channel} peaks at {peak:.3}, not at 1",
                    stock.id
                );
                assert!(
                    table.iter().all(|value| *value >= 0.0),
                    "{} dye {channel} has a negative density",
                    stock.id
                );
            }
            assert!(
                stock.mask.iter().all(|value| *value >= 0.0),
                "{} has a negative mask density",
                stock.id
            );
            for (channel, table) in stock.layers.iter().enumerate() {
                let peak = table.iter().copied().fold(0.0_f64, f64::max);
                assert!(
                    peak > 0.0,
                    "{} layer {channel} is dark everywhere",
                    stock.id
                );
                assert!(
                    table.iter().all(|value| *value >= 0.0),
                    "{} layer {channel} has a negative sensitivity",
                    stock.id
                );
            }
        }
    }

    /// Each colour layer records where its own sheet says it does.
    ///
    /// The failure this catches is a panel read the wrong way round. The three
    /// curves are labelled by the dye they form — Cyan-, Magenta- and
    /// Yellow-Forming — and an extractor that assigns them by position instead
    /// of by label can put the cyan layer's peak in the blue, produce three
    /// smooth plausible tables, and never fail anything else. GOLD 200's sheet
    /// draws four strokes for three layers, so the risk is not hypothetical.
    #[test]
    fn every_colour_layer_peaks_in_its_own_band() {
        for stock in FILM_STOCKS {
            if stock.process == FilmProcess::Monochrome {
                continue;
            }
            for (layer, low, high) in [(0, 590.0, 700.0), (1, 490.0, 600.0), (2, 380.0, 500.0)] {
                let (index, value) = stock.layers[layer].iter().enumerate().fold(
                    (0, f64::NEG_INFINITY),
                    |best, (i, &v)| {
                        if v > best.1 { (i, v) } else { best }
                    },
                );
                let wavelength = 380.0 + 5.0 * index as f64;
                assert!(
                    (low..=high).contains(&wavelength),
                    "{} layer {layer} peaks at {wavelength} nm, outside {low}-{high}",
                    stock.id
                );
                assert!(
                    value > 0.0,
                    "{} layer {layer} is dark at its peak",
                    stock.id
                );
            }
        }
    }

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
            // A reversal is the exception, and not a small one: its unexposed
            // film is its densest state, so the curve starts at about 3.4 and
            // falls to clear. A negative's curve is dye above base and starts at
            // zero; a reversal's is the picture and starts at its maximum.
            let reversal = stock.process == FilmProcess::Reversal;
            for (layer, channel) in stock.channels.iter().enumerate() {
                if reversal {
                    assert!(
                        channel.d_min > channel.d_max,
                        "{} layer {layer}: reversal curve rises, d_min {} d_max {}",
                        stock.id,
                        channel.d_min,
                        channel.d_max
                    );
                } else {
                    assert!(
                        channel.d_min.abs() < 1e-9,
                        "{} layer {layer}: d_min {}",
                        stock.id,
                        channel.d_min
                    );
                }
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
                (paper.channel.toe_transition - transition).abs() < 1e-9,
                "{id}: transition {}, not the {transition} its sheet fitted",
                paper.channel.toe_transition
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

    /// ADR 0017 is wired, and this is what keeps its blast radius visible: no
    /// stock in the tree declares a second cyan emulsion yet, so every stock
    /// renders through the three-layer path exactly as it did before.
    #[test]
    fn no_stock_has_a_second_cyan_emulsion_yet() {
        for stock in FILM_STOCKS {
            assert!(stock.extra_cyan.is_none(), "{} declares one", stock.id);
        }
    }
}
