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
use crate::measured::{PAPER_DYES, PAPER_DYES_E4021, PAPER_LAYERS, PAPER_LAYERS_E4021};
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
        process: FilmProcess::Negative,
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
        // H-1-5219 page 4, digitised at 5 nm and normalised by one constant
        // across the three, so the layers' relative speed survives.
        layers: &kallotype_spectral::layers::CHANNELS,
        // The dye curves are peak-normalised absorption; the mask is the
        // minimum-density spectrum from the same page.
        dyes: &crate::measured::FILM_DYES,
        mask: &crate::measured::FILM_MASK,
        sigma_um: None,
    },
    FilmStock {
        id: "c41_standard",
        process: FilmProcess::Negative,
        label: "Colour negative, standard development",
        note: "Placeholder C-41 curve: moderate contrast, even layer speeds.",
        channels: [
            curve(0.0, 2.08, 0.60, -0.75),
            curve(0.0, 2.11, 0.63, -0.75),
            curve(0.0, 2.14, 0.66, -0.76),
        ],
        base_density: [0.22, 0.22, 0.22],
        grains_per_um2: [3.6, 3.6, 3.6],
        // A placeholder has to put *something* here. This one borrows the
        // measured VISION3 spectra, which is why its note still says
        // placeholder: the curve is invented and the colour response is not
        // its own.
        layers: &kallotype_spectral::layers::CHANNELS,
        dyes: &crate::measured::FILM_DYES,
        mask: &crate::measured::FILM_MASK,
        sigma_um: None,
    },
    FilmStock {
        id: "c41_contrast",
        process: FilmProcess::Negative,
        label: "Colour negative, high-contrast",
        note: "Placeholder C-41 curve with a steeper shoulder and stronger layer separation.",
        channels: [
            curve(0.0, 2.25, 0.70, -0.72),
            curve(0.0, 2.28, 0.73, -0.73),
            curve(0.0, 2.31, 0.76, -0.74),
        ],
        base_density: [0.20, 0.20, 0.20],
        grains_per_um2: [3.6, 3.6, 3.6],
        layers: &kallotype_spectral::layers::CHANNELS,
        dyes: &crate::measured::FILM_DYES,
        mask: &crate::measured::FILM_MASK,
        sigma_um: None,
    },
    FilmStock {
        id: "bw_classic",
        process: FilmProcess::Negative,
        label: "Black and white, classic",
        note: "Placeholder B&W curve: identical layers, longer straight line.",
        channels: [
            curve(0.0, 2.50, 0.58, -0.80),
            curve(0.0, 2.50, 0.58, -0.80),
            curve(0.0, 2.50, 0.58, -0.80),
        ],
        base_density: [0.10, 0.10, 0.10],
        grains_per_um2: [3.6, 3.6, 3.6],
        // A B&W film has one emulsion, not three: all three entries are the
        // same curve, and the spectra are borrowed until one is digitised.
        layers: &kallotype_spectral::layers::CHANNELS,
        dyes: &crate::measured::FILM_DYES,
        mask: &crate::measured::FILM_MASK,
        sigma_um: None,
    },
    // A measurement may sit on a constant by chance — the 200T's blue layer
    // blurs to 3.14 µm — and the lint is about literals meant to be pi.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    FilmStock {
        id: "fuji_nph400",
        process: FilmProcess::Negative,
        label: "FUJICOLOR NPH 400 PROFESSIONAL (NPH)",
        note: "Measured, except for the dyes and the mask. Curves from data sheet AF3-865E page 6, digitised 2026-11-07; layer sensitivities from figure 19 on the same page. Figure 21 publishes the density of a mid-scale neutral subject rather than the three dyes separately, so the dye shapes are borrowed from the VISION3 digitisation and the mask with them — which is why this stock is not yet as measured as it looks.",
        channels: [
            curve(0.0, 2.8856, 0.7520, -0.6371).with_transition(3.0),
            curve(0.0, 2.6366, 0.8859, -1.1100).with_transition(3.0),
            curve(0.0, 3.4299, 0.8066, -0.4871).with_transition(3.0),
        ],
        base_density: [0.2053, 0.3996, 0.7863],
        grains_per_um2: [5.4200, 5.4200, 5.4200],
        layers: &crate::measured::FUJI_NPH400_LAYERS,
        dyes: &crate::measured::FILM_DYES,
        mask: &crate::measured::FILM_MASK,
        sigma_um: None,
    },
    // A measurement may sit on a constant by chance — the 200T's blue layer
    // blurs to 3.14 µm — and the lint is about literals meant to be pi.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    FilmStock {
        id: "kodak_portra_400",
        process: FilmProcess::Negative,
        label: "KODAK PROFESSIONAL PORTRA 400",
        note: "Generated from kodak_portra_400.toml; borrowed: spectra.dyes; grain is the compiled placeholder, not a measurement",
        channels: [
            curve(0.0, 1.6578, 0.6299, -0.6947),
            curve(0.0, 1.7095, 0.6276, -0.7407),
            curve(0.0, 2.0460, 0.7204, -0.7987),
        ],
        base_density: [0.2156, 0.6302, 0.8476],
        grains_per_um2: [0.62, 0.51, 0.07],
        layers: &crate::measured::KODAK_PORTRA400_LAYERS,
        dyes: &crate::measured::FILM_DYES,
        mask: &crate::measured::FILM_MASK,
        sigma_um: Some([4.4500, 3.4100, 3.0800]),
    },
    // A measurement may sit on a constant by chance — the 200T's blue layer
    // blurs to 3.14 µm — and the lint is about literals meant to be pi.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    FilmStock {
        id: "kodak_ektar_100",
        process: FilmProcess::Negative,
        label: "KODAK PROFESSIONAL EKTAR 100",
        note: "Generated from kodak_ektar_100.toml; borrowed: spectra.dyes; grain is the compiled placeholder, not a measurement",
        channels: [
            curve(0.0, 1.6713, 0.6038, -0.7120),
            curve(0.0, 1.6693, 0.5911, -0.7400),
            curve(0.0, 2.0919, 0.7193, -0.7820),
        ],
        base_density: [0.2184, 0.6436, 0.8535],
        grains_per_um2: [0.62, 0.51, 0.07],
        layers: &crate::measured::KODAK_EKTAR100_LAYERS,
        dyes: &crate::measured::FILM_DYES,
        mask: &crate::measured::FILM_MASK,
        sigma_um: Some([4.8700, 3.6700, 3.4900]),
    },
    // A measurement may sit on a constant by chance — the 200T's blue layer
    // blurs to 3.14 µm — and the lint is about literals meant to be pi.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    FilmStock {
        id: "kodak_gold200",
        process: FilmProcess::Negative,
        label: "KODAK GOLD 200",
        note: "Generated from kodak_gold200.toml; borrowed: spectra.dyes, emulsion.sigma_um; grain is the compiled placeholder, not a measurement",
        channels: [
            curve(0.0, 1.5411, 0.5473, -0.7300),
            curve(0.0, 1.6367, 0.5659, -0.7680),
            curve(0.0, 1.7876, 0.6321, -0.7360),
        ],
        base_density: [0.2611, 0.6662, 0.9944],
        grains_per_um2: [0.62, 0.51, 0.07],
        layers: &crate::measured::KODAK_GOLD200_LAYERS,
        dyes: &crate::measured::FILM_DYES,
        mask: &crate::measured::FILM_MASK,
        sigma_um: None,
    },
    // A measurement may sit on a constant by chance — the 200T's blue layer
    // blurs to 3.14 µm — and the lint is about literals meant to be pi.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    FilmStock {
        id: "kodak_portra_160",
        process: FilmProcess::Negative,
        label: "KODAK PROFESSIONAL PORTRA 160",
        note: "Generated from kodak_portra_160.toml; borrowed: spectra.dyes; grain is the compiled placeholder, not a measurement",
        channels: [
            curve(0.0, 1.5459, 0.5658, -0.7281),
            curve(0.0, 1.6641, 0.6012, -0.7461),
            curve(0.0, 1.9107, 0.6834, -0.7601),
        ],
        base_density: [0.1995, 0.6101, 0.8417],
        grains_per_um2: [0.62, 0.51, 0.07],
        layers: &crate::measured::KODAK_PORTRA160_LAYERS,
        dyes: &crate::measured::FILM_DYES,
        mask: &crate::measured::FILM_MASK,
        sigma_um: Some([4.8400, 3.0700, 3.4400]),
    },
    // A measurement may sit on a constant by chance — the 200T's blue layer
    // blurs to 3.14 µm — and the lint is about literals meant to be pi.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    FilmStock {
        id: "kodak_portra_800",
        process: FilmProcess::Negative,
        label: "KODAK PROFESSIONAL PORTRA 800",
        note: "Generated from kodak_portra_800.toml; borrowed: spectra.dyes; grain is the compiled placeholder, not a measurement",
        channels: [
            curve(0.0, 1.5435, 0.5855, -0.7187),
            curve(0.0, 1.6521, 0.5926, -0.7947),
            curve(0.0, 1.8100, 0.6856, -0.7207),
        ],
        base_density: [0.3232, 0.7114, 1.0423],
        grains_per_um2: [0.62, 0.51, 0.07],
        layers: &crate::measured::KODAK_PORTRA800_LAYERS,
        dyes: &crate::measured::FILM_DYES,
        mask: &crate::measured::FILM_MASK,
        sigma_um: Some([4.7500, 3.7000, 3.0000]),
    },
    // A measurement may sit on a constant by chance — the 200T's blue layer
    // blurs to 3.14 µm — and the lint is about literals meant to be pi.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    FilmStock {
        id: "fuji_c200",
        process: FilmProcess::Negative,
        label: "FUJICOLOR C200",
        note: "Measured, except for the dyes and the mask. Every chart is a 1-bit mask: characteristic curves, sensitivity, MTF and the dye panel are artwork rather than renders. Two traps on the page. The sensitivity chart is five images — two raster strips with the seam through the middle of the plot, and the decade line the curves stand on — and is reassembled from their page coordinates before it is read. And the characteristic curves name their layers in white lozenges painted over the curves, so the columns are paired by order rather than followed by continuity: a characteristic plot's three layers differ in speed, not shape. The MTF panel publishes one curve for the film, which is why all three layers carry the same blur.",
        channels: [
            curve(0.0, 2.3726, 0.5974, -0.6739),
            curve(0.0, 2.6085, 0.6530, -0.6738),
            curve(0.0, 2.4459, 0.6764, -0.8865),
        ],
        base_density: [0.1410, 0.4131, 0.7210],
        grains_per_um2: [5.4200, 5.4200, 5.4200],
        layers: &crate::measured::FUJI_C200_LAYERS,
        dyes: &crate::measured::FILM_DYES,
        mask: &crate::measured::FILM_MASK,
        sigma_um: Some([3.3800, 3.3800, 3.3800]),
    },
    // A measurement may sit on a constant by chance — the 200T's blue layer
    // blurs to 3.14 µm — and the lint is about literals meant to be pi.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    FilmStock {
        id: "fuji200",
        process: FilmProcess::Negative,
        label: "FUJIFILM 200 Color Negative Film",
        note: "Measured, except for the dyes, the mask and the blur. Curves and layer sensitivities are this sheet's; figure 16 prints a mid-scale neutral rather than three dyes, and the sheet carries no MTF panel and no granularity figure, so the dye shapes, the mask and the blur are the compiled ones.",
        channels: [
            curve(0.0, 1.9123, 0.5333, -0.8183),
            curve(0.0, 2.1830, 0.6311, -0.9264),
            curve(0.0, 2.5467, 0.6156, -0.4895),
        ],
        base_density: [0.1375, 0.3292, 0.8267],
        grains_per_um2: [0.62, 0.51, 0.07],
        layers: &crate::measured::FUJI200_LAYERS,
        dyes: &crate::measured::FILM_DYES,
        mask: &crate::measured::FILM_MASK,
        sigma_um: None,
    },
    // A measurement may sit on a constant by chance — the 200T's blue layer
    // blurs to 3.14 µm — and the lint is about literals meant to be pi.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    FilmStock {
        id: "fuji400",
        process: FilmProcess::Negative,
        label: "FUJIFILM 400 Color Negative Film",
        note: "Measured, except for the dyes, the mask and the blur. Curves and layer sensitivities are this sheet's; figure 16 prints a mid-scale neutral rather than three dyes, and the sheet carries no MTF panel and no granularity figure, so the dye shapes, the mask and the blur are the compiled ones.",
        channels: [
            curve(0.0, 2.1944, 0.5696, -0.7423),
            curve(0.0, 2.3913, 0.6415, -0.9248),
            curve(0.0, 2.6525, 0.6022, -0.5670),
        ],
        base_density: [0.1793, 0.3869, 0.8946],
        grains_per_um2: [0.62, 0.51, 0.07],
        layers: &crate::measured::FUJI400_LAYERS,
        dyes: &crate::measured::FILM_DYES,
        mask: &crate::measured::FILM_MASK,
        sigma_um: None,
    },
    // A measurement may sit on a constant by chance — the 200T's blue layer
    // blurs to 3.14 µm — and the lint is about literals meant to be pi.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    FilmStock {
        id: "vision3_250d",
        process: FilmProcess::Negative,
        label: "KODAK VISION3 250D 5207/7207, ECN-2",
        note: "Measured: curves, base density, modulation transfer and the three layer sensitivities, each from its own raster on H-1-5207. The dyes were digitised too and compared against the 500T's compiled tables — the model carries one dye set, and this sheet's agrees with it to 0.12 density and 5 nm, which is why the shared set is kept rather than duplicated. Borrowed: the grain density (this sheet's granularity chart defeats the dot tracker; see the header) and the mask, which is the 500T's minimum-density spectrum.",
        channels: [
            curve(0.0, 1.6714, 0.4745, -0.7697),
            curve(0.0, 1.9925, 0.5573, -0.7182),
            curve(0.0, 1.9037, 0.5428, -0.7463),
        ],
        base_density: [0.1742, 0.5739, 0.8354],
        grains_per_um2: [0.6200, 0.5100, 0.0700],
        layers: &crate::measured::VISION3_250D_LAYERS,
        dyes: &crate::measured::FILM_DYES,
        mask: &crate::measured::FILM_MASK,
        sigma_um: Some([4.2500, 3.3400, 3.0900]),
    },
    // A measurement may sit on a constant by chance — the 200T's blue layer
    // blurs to 3.14 µm — and the lint is about literals meant to be pi.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    FilmStock {
        id: "vision3_50d",
        process: FilmProcess::Negative,
        label: "KODAK VISION3 50D 5203/7203, ECN-2",
        note: "Measured: curves, base density, modulation transfer and the three layer sensitivities. The sheet's red characteristic curve is dotted and the tracker reads it as such. Its sensitivity chart prints its tick labels in the wrong place — the ticks and rules agree on a 0-4 axis, the printed numbers do not — and the axis is taken from the ticks (see the header). Borrowed: the grain density, which this sheet's granularity chart does not give up to the dot tracker, and the mask, which is the 500T's minimum-density spectrum.",
        channels: [
            curve(0.0, 1.7439, 0.5024, -0.7995),
            curve(0.0, 2.0727, 0.5937, -0.7195),
            curve(0.0, 1.9992, 0.5719, -0.7152),
        ],
        base_density: [0.1457, 0.5574, 0.8393],
        grains_per_um2: [0.6200, 0.5100, 0.0700],
        layers: &crate::measured::VISION3_50D_LAYERS,
        dyes: &crate::measured::FILM_DYES,
        mask: &crate::measured::FILM_MASK,
        sigma_um: Some([4.5300, 4.4100, 4.2600]),
    },
    // A measurement may sit on a constant by chance — the 200T's blue layer
    // blurs to 3.14 µm — and the lint is about literals meant to be pi.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    FilmStock {
        id: "vision3_200t",
        process: FilmProcess::Negative,
        label: "KODAK VISION3 200T 5213/7213, ECN-2",
        note: "Measured: curves, base density, modulation transfer and the three layer sensitivities. Two traps on the page: the dye panel's process note is printed inside the plot and has to be masked, and the sensitivity chart's cyan curve starts at a dip, so its tails are clamped rather than extrapolated. Borrowed: the grain density, which this sheet's granularity chart does not give up, and the mask, which is the 500T's minimum-density spectrum.",
        channels: [
            curve(0.0, 1.6591, 0.4825, -0.7771),
            curve(0.0, 1.9752, 0.5652, -0.7227),
            curve(0.0, 1.8847, 0.5411, -0.7344),
        ],
        base_density: [0.1683, 0.5679, 0.8369],
        grains_per_um2: [0.6200, 0.5100, 0.0700],
        layers: &crate::measured::VISION3_200T_LAYERS,
        dyes: &crate::measured::FILM_DYES,
        mask: &crate::measured::FILM_MASK,
        sigma_um: Some([4.2500, 3.4900, 3.1400]),
    },
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    FilmStock {
        id: "provia_100f",
        process: FilmProcess::Reversal,
        label: "FUJICHROME PROVIA 100F (RDP III), E-6",
        note: "Measured: the characteristic curves, the three dyes, the layer sensitivities and the modulation transfer. The sensitivity panel is the only one in the archive drawn as vector paths rather than a raster, and was read from its Bezier segments. The three characteristic curves are separated ink plates, so red is complete and the green and blue layers carry its shape with their own measured offsets — residuals 0.009 and 0.051. The MTF panel publishes one curve for the film and all three layers carry it. The grain is derived from the sheet's diffuse rms granularity value of 8 through the same inversion the C200 stock used, not from a curve.",
        channels: [
            curve(3.3124, 0.0787, 2.0838, -1.2296),
            curve(3.3474, 0.1137, 2.0838, -1.1796),
            curve(3.4624, 0.2287, 2.0838, -1.2596),
        ],
        base_density: [0.0000, 0.0000, 0.0000],
        grains_per_um2: [6.1700, 6.1700, 6.1700],
        layers: &crate::measured::PROVIA_100F_LAYERS,
        dyes: &crate::measured::PROVIA_100F_DYES,
        mask: &crate::measured::NO_MASK,
        sigma_um: Some([4.6800, 4.6800, 4.6800]),
    },
    // A measured value can land on a mathematical constant by coincidence; the
    // lint is about literals that were meant to be that constant.
    #[allow(clippy::approx_constant)]
    FilmStock {
        id: "ilford_delta400",
        process: FilmProcess::Monochrome,
        label: "ILFORD DELTA 400 PROFESSIONAL, ID-11 8 min 24 °C",
        note: "Measured: the characteristic curve from page 6 and its toe as the base density. The sheet publishes no spectral sensitivity chart, so the layer response is flat across the visible — the definition of panchromatic and the only claim the sheet supports, not a measurement. No MTF panel and no granularity figure: the blur is not modelled and the grain is the compiled placeholder, averaged across the three channels so a silver image stays neutral.",
        channels: [
            curve(0.0, 2.0349, 0.7025, -0.7447),
            curve(0.0, 2.0349, 0.7025, -0.7447),
            curve(0.0, 2.0349, 0.7025, -0.7447),
        ],
        base_density: [0.2654, 0.2654, 0.2654],
        grains_per_um2: [0.4000, 0.4000, 0.4000],
        layers: &crate::measured::ILFORD_DELTA400_LAYERS,
        dyes: &crate::measured::NO_DYES,
        mask: &crate::measured::NO_MASK,
        sigma_um: None,
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

    /// The second film is not the first one with another curve.
    ///
    /// Its layer sensitivities were digitised from its own data sheet, and its
    /// curves turn their corners at 3 rather than 4. A stock that borrowed the
    /// first film's tables would render the same colour with a different
    /// contrast, which is the thing this field exists to prevent.
    #[test]
    fn the_second_film_has_its_own_layers() {
        let fuji = film_stock("fuji_nph400").expect("built-in stock");
        let kodak = film_stock("vision3_500t").expect("built-in stock");
        assert_eq!(fuji.channels[0].transition, 3.0);
        assert_eq!(kodak.channels[0].transition, crate::curve::TRANSITION);
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
