//! The render: a negative is exposed, developed, and printed.
//!
//! Phase 0 keeps a single scalar per channel. There is no spectrum yet, but
//! the *shape* of the computation is already the final one: light becomes
//! density on the negative, the negative becomes light again in the enlarger,
//! and that light becomes density on the paper.
//!
//! ```text
//! E ──► D_neg ──► T = 10^-D ──► D_print ──► R = 10^-D
//!        ▲                          ▲
//!    H&D curve                 paper curve,
//!  (development)              balanced on 18 % grey
//! ```

use crate::curve::CharacteristicCurve;
use crate::development::DevelopmentParams;
use crate::emulsion::{FilmStock, PaperStock};
use crate::lut::ExposureLut;
use crate::model::SpectralModel;
use crate::print::PrintContext;
use crate::scan::ScanContext;
use crate::spectral::{CameraProfile, SpectralContext};

/// log10 of the luminance a mid-grey card reflects. The anchor everything is
/// balanced against; 0.18 is the conventional value.
#[must_use]
pub fn mid_grey_log_e() -> f64 {
    0.18_f64.log10()
}

/// Everything needed to render: which film, which paper, and how it was developed.
#[derive(Debug, Clone)]
pub struct RenderParams {
    /// The negative.
    pub film: &'static FilmStock,
    /// The paper it is printed on.
    pub paper: &'static PaperStock,
    /// How the negative was developed.
    pub development: DevelopmentParams,
    /// Exposure offset in stops, applied before the negative is exposed.
    pub exposure_ev: f64,
    /// Expose through the spectral path instead of the per-channel scalar one.
    pub spectral: bool,
    /// Which sensor the input RGB is assumed to have come from. Ignored by the
    /// scalar path.
    pub camera: CameraProfile,
    /// Bake the spectral exposure into a `size^3` table. Zero disables it.
    pub lut_size: usize,
    /// Print through spectral dye absorption and paper layer sensitivities.
    pub spectral_print: bool,
    /// Scan through spectral reflectance, illuminant and observer.
    pub spectral_scan: bool,
}

impl Default for RenderParams {
    fn default() -> Self {
        Self {
            film: crate::emulsion::film_stock("vision3_500t").expect("built-in stock"),
            paper: crate::emulsion::paper_stock("c41_paper").expect("built-in stock"),
            development: DevelopmentParams::default(),
            exposure_ev: 0.0,
            spectral: false,
            camera: CameraProfile::default(),
            lut_size: 0,
            spectral_print: false,
            spectral_scan: false,
        }
    }
}

impl RenderParams {
    /// Freeze the development-dependent curves and solve the print balance.
    #[must_use]
    pub fn prepare(&self) -> PreparedRender {
        self.prepare_with(None)
    }

    /// Prepare with a table loaded from disk instead of baking one.
    ///
    /// The table was baked from some camera, film and dictionary; the caller is
    /// responsible for it matching this render's film. The format carries no
    /// model identity yet, which is a known gap.
    #[must_use]
    pub fn prepare_with_lut(&self, lut: ExposureLut) -> PreparedRender {
        let mut prepared = Self {
            spectral: false,
            lut_size: 0,
            ..self.clone()
        }
        .prepare_with(None);
        prepared.lut = Some(lut);
        prepared
    }

    /// As [`Self::prepare`], with an optional dictionary for the spectral prior.
    ///
    /// The atoms are what the hybrid needs; without them the spectral path uses
    /// the polynomial prior alone.
    #[must_use]
    pub fn prepare_with(&self, atoms: Option<&[kallotype_spectral::Spectrum]>) -> PreparedRender {
        let channels: [CharacteristicCurve; 3] =
            std::array::from_fn(|i| self.development.apply_to(self.film.channels[i]));

        let paper = self.paper.channel;

        // Solve the enlarger exposure so that a mid-grey negative prints at
        // the paper's target reflectance. This is what an operator does with
        // the aperture and the test strip, done in closed form: find the log
        // exposure at which the paper reaches the target density, and shift the
        // enlarger's exposure by however far mid grey is from it.
        let target_density = -self.paper.target_mid_reflectance.log10();
        let target_log_e = paper.log_exposure_at(target_density);

        let mid = mid_grey_log_e();
        let density_mid: [f64; 3] = std::array::from_fn(|i| channels[i].density(mid));

        // Two ways to describe what reaches the paper. The scalar one treats each
        // density as that channel's light loss; the spectral one integrates the
        // dyes' absorption bands against the paper's layer sensitivities.
        let print = self
            .spectral_print
            .then(|| PrintContext::measured(density_mid));
        let print_shift: [f64; 3] = match &print {
            // The spectral model is anchored on neutral grey, so the actual
            // mid-grey exposure is subtracted here rather than assumed to be 0.
            Some(context) => {
                let mid_exposure = context.expose(density_mid);
                std::array::from_fn(|i| target_log_e - mid_exposure[i])
            }
            // The non-spectral print has no mask to add, so the film's base
            // density goes into the exponent with the dye.
            None => {
                std::array::from_fn(|i| target_log_e + density_mid[i] + self.film.base_density[i])
            }
        };

        PreparedRender {
            channels,
            base_density: self.film.base_density,
            paper,
            print_shift,
            print,
            scan: self.spectral_scan.then(ScanContext::measured),
            exposure_shift: self.exposure_ev * 2.0_f64.log10(),
            spectral: self
                .spectral
                .then(|| {
                    let context = SpectralContext::new().with_camera(self.camera.clone());
                    match atoms {
                        Some(atoms) => context.with_atoms(atoms),
                        None => context,
                    }
                })
                .filter(|_| self.lut_size < 2),
            lut: (self.spectral && self.lut_size >= 2).then(|| {
                let context = SpectralContext::new().with_camera(self.camera.clone());
                let context = match atoms {
                    Some(atoms) => context.with_atoms(atoms),
                    None => context,
                };
                ExposureLut::bake(self.lut_size, &context)
            }),
        }
    }
}

/// The scalar model, flattened into the numbers another backend needs.
///
/// A GPU cannot call into this crate, and re-deriving the model from its
/// parameters on the other side would be a second implementation that could
/// drift. So the prepared render hands over the numbers it solved, in the shape
/// a shader wants: per layer, a base density, a span, a slope and an inflection
/// point; then the paper's two numbers and the enlarger's four.
///
/// Only the pure scalar path has one. The spectral exposure, the spectral print
/// and the spectral scan integrate over wavelength, and a backend that wants
/// them has to port the integration rather than the numbers.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ScalarModel {
    /// Per layer: `d_min`, `d_max`, `gamma`, `log_e0`.
    pub curve: [[f64; 4]; 3],
    /// The paper's `d_min`, `d_max`, `gamma` and `log_e0`.
    pub paper: [f64; 4],
    /// The film's minimum density in status terms: base, fog and mask.
    pub base_density: [f64; 3],
    /// The enlarger's exposure shift per layer, in decades.
    pub print_shift: [f64; 3],
    /// Exposure offset applied before the curve, in decades.
    pub exposure_shift: f64,
}

/// A [`RenderParams`] with the curves already developed and the print balanced.
#[derive(Debug, Clone)]
pub struct PreparedRender {
    channels: [CharacteristicCurve; 3],
    base_density: [f64; 3],
    paper: CharacteristicCurve,
    print_shift: [f64; 3],
    exposure_shift: f64,
    /// The live spectral model, when no table was baked.
    spectral: Option<SpectralContext>,
    /// The baked table, when one was requested.
    lut: Option<ExposureLut>,
    /// The spectral print model, when requested.
    print: Option<PrintContext>,
    /// The spectral scan model, when requested.
    scan: Option<ScanContext>,
}

impl PreparedRender {
    /// The curve, the paper and the enlarger as plain numbers.
    ///
    /// Always available, because a spectral render runs the same three stages:
    /// it only reaches the paper through an integration instead of through a
    /// per-channel subtraction.
    fn numbers(&self) -> ScalarModel {
        ScalarModel {
            curve: std::array::from_fn(|layer| {
                let curve = &self.channels[layer];
                [curve.d_min, curve.d_max, curve.gamma, curve.log_e0]
            }),
            paper: [
                self.paper.d_min,
                self.paper.d_max,
                self.paper.gamma,
                self.paper.log_e0,
            ],
            base_density: self.base_density,
            print_shift: self.print_shift,
            exposure_shift: self.exposure_shift,
        }
    }

    /// The scalar model as plain numbers, when the render uses only the scalar
    /// path. `None` the moment any spectral stage is active.
    #[must_use]
    pub fn scalar_model(&self) -> Option<ScalarModel> {
        if self.spectral.is_some()
            || self.lut.is_some()
            || self.print.is_some()
            || self.scan.is_some()
        {
            return None;
        }
        Some(self.numbers())
    }

    /// The spectral model as plain numbers, when this render integrates over
    /// wavelength and nothing in it needs a solver or a sampled cube.
    ///
    /// `None` in three cases, and the distinction matters to a caller that has
    /// to choose a backend rather than to a caller that has to render:
    ///
    /// - nothing is spectral, so [`Self::scalar_model`] describes it;
    /// - a baked table is in use, which is a sampled approximation rather than
    ///   an integration;
    /// - a dictionary prior is in use, which solves a non-negative least
    ///   squares per pixel instead of a fixed matrix.
    ///
    /// The last two are their own models. A backend that implemented them would
    /// be porting a solver, not replaying numbers, and it should say so rather
    /// than substitute the closed form.
    #[must_use]
    pub fn spectral_model(&self) -> Option<SpectralModel> {
        if self.lut.is_some() {
            return None;
        }
        // All three stages integrate on the model grid, so the first one that
        // is present carries the step and the others cannot disagree.
        let step_nm = self
            .spectral
            .as_ref()
            .map(|context| context.grid().step_nm())
            .or_else(|| self.print.as_ref().map(|context| context.grid().step_nm()))
            .or_else(|| self.scan.as_ref().map(|context| context.grid().step_nm()))
            .unwrap_or(0.0);
        let model = SpectralModel {
            scalar: self.numbers(),
            step_nm,
            exposure: match &self.spectral {
                Some(context) => Some(context.model()?),
                None => None,
            },
            enlarger: match &self.print {
                Some(context) => Some(context.model()?),
                None => None,
            },
            scan: match &self.scan {
                Some(context) => Some(context.model()?),
                None => None,
            },
        };
        model.is_spectral().then_some(model)
    }

    /// The three negative curves after development.
    #[must_use]
    pub fn channels(&self) -> &[CharacteristicCurve; 3] {
        &self.channels
    }

    /// Whether the spectral path is active, baked or live.
    #[must_use]
    pub fn is_spectral(&self) -> bool {
        self.spectral.is_some() || self.lut.is_some()
    }

    /// Whether the print is going through the spectral model.
    #[must_use]
    pub fn is_spectral_print(&self) -> bool {
        self.print.is_some()
    }

    /// Whether the scan is going through the spectral model.
    #[must_use]
    pub fn is_spectral_scan(&self) -> bool {
        self.scan.is_some()
    }

    /// The baked table, if one was requested.
    #[must_use]
    pub fn lut(&self) -> Option<&ExposureLut> {
        self.lut.as_ref()
    }

    /// The three log exposures: scalar per channel, or the film's layers
    /// integrating a reconstructed spectrum.
    #[must_use]
    pub fn log_exposure(&self, linear: [f64; 3]) -> [f64; 3] {
        let scalar = || std::array::from_fn(|channel| linear[channel].max(1e-10).log10());
        if let Some(lut) = &self.lut {
            // Baked: three trilinear lookups.
            lut.sample(linear)
        } else if let Some(context) = &self.spectral {
            // Live: reconstruct and integrate. The fallback keeps the function
            // total; it cannot trigger with a context this module built.
            context.expose(linear).unwrap_or_else(scalar)
        } else {
            scalar()
        }
    }

    /// The negative's density, from log exposure.
    #[must_use]
    pub fn negative_density(&self, log_e: [f64; 3]) -> [f64; 3] {
        std::array::from_fn(|channel| {
            self.channels[channel].density(log_e[channel] + self.exposure_shift)
        })
    }

    /// The print and the scan, from the negative's density.
    #[must_use]
    pub fn positive(&self, density_cmy: [f64; 3]) -> [f64; 3] {
        // The spectral print does one integration for all three layers; calling
        // it inside the channel loop made it six times more expensive per pixel.
        let print_exposure = self
            .print
            .as_ref()
            .map(|context| context.expose(density_cmy));

        let mut density_print = [0.0; 3];
        for channel in 0..3 {
            // The enlarger sees the light the negative transmitted: per channel
            // in the scalar model, through the dye spectra in the spectral one.
            // The non-spectral print has no spectrum for the base, so the
            // film's minimum density rides in the exponent with the dye. The
            // spectral one puts the measured mask into the integral instead.
            let log_transmittance = match &print_exposure {
                Some(values) => values[channel],
                None => -(density_cmy[channel] + self.base_density[channel]),
            };
            density_print[channel] = self
                .paper
                .density(log_transmittance + self.print_shift[channel]);
        }

        match &self.scan {
            // Spectral scan: reflectance through the illuminant and the observer.
            Some(context) => context.scan(density_print),
            // Scalar scan: each density is that channel's light loss.
            None => density_print.map(|density| 10.0_f64.powf(-density).clamp(0.0, 1.0)),
        }
    }

    /// Curve, print and scan for one pixel, with optional grain on the exposure.
    fn finish(
        &self,
        log_e: [f64; 3],
        x: usize,
        y: usize,
        grain: Option<&crate::grain::GrainField>,
    ) -> [f64; 3] {
        let density = self.negative_density(log_e);
        let jittered: [f64; 3] = match grain {
            Some(grain) => std::array::from_fn(|channel| {
                log_e[channel] + grain.jitter(x, y, density[channel], channel)
            }),
            None => log_e,
        };
        self.positive(self.negative_density(jittered))
    }

    /// Render one linear-light pixel.
    #[must_use]
    pub fn render_pixel(&self, linear: [f64; 3]) -> [f64; 3] {
        self.positive(self.negative_density(self.log_exposure(linear)))
    }
}

/// What happens between the exposure and the development.
///
/// Both are optional and independent; the model without them is the model.
#[derive(Debug, Clone, Copy, Default)]
pub struct Finishing<'a> {
    /// Light that scatters in the emulsion and reflects off the base.
    pub halation: Option<&'a crate::halation::Halation>,
    /// The emulsion's grain.
    pub grain: Option<&'a crate::grain::GrainField>,
    /// DIR couplers, acting on the developed densities.
    pub couplers: Option<&'a crate::couplers::Couplers>,
}

/// Render a whole image with the finishing effects.
///
/// Halation runs first and needs the whole frame, because it moves light
/// between pixels; grain runs second and is per pixel. Both are applied to the
/// exposure — one to where the light went, one to how many grains it developed —
/// which is why they sit before the curve rather than after the print.
pub fn render_pixels_finished(
    pixels: &mut [[f64; 3]],
    prepared: &PreparedRender,
    width: usize,
    height: usize,
    finishing: &Finishing,
) {
    let width = width.max(1);

    // Without a spatial effect there is nothing to keep a frame for.
    if finishing.halation.is_none() && finishing.couplers.is_none() {
        for (index, pixel) in pixels.iter_mut().enumerate() {
            let (x, y) = (index % width, index / width);
            let log_e = prepared.log_exposure(*pixel);
            *pixel = prepared.finish(log_e, x, y, finishing.grain);
        }
        return;
    }

    // Exposure first: halation moves light between pixels, before anything is
    // developed.
    let mut log_e: Vec<[f64; 3]> = pixels
        .iter()
        .map(|pixel| prepared.log_exposure(*pixel))
        .collect();
    if let Some(halation) = finishing.halation {
        halation.apply(&mut log_e, width, height);
    }

    // Then the emulsion: grain on the exposure, the curve on the result.
    let mut density: Vec<[f64; 3]> = log_e
        .iter()
        .enumerate()
        .map(|(index, log_e)| {
            let mean = prepared.negative_density(*log_e);
            match finishing.grain {
                Some(grain) => prepared.negative_density(std::array::from_fn(|channel| {
                    log_e[channel]
                        + grain.jitter(index % width, index / width, mean[channel], channel)
                })),
                None => mean,
            }
        })
        .collect();

    // Then the chemistry: the inhibitors act on what has already developed.
    if let Some(couplers) = finishing.couplers {
        couplers.apply(&mut density, width, height);
    }

    for (pixel, density) in pixels.iter_mut().zip(density) {
        *pixel = prepared.positive(density);
    }
}

/// Render a whole image in place.
pub fn render_pixels(pixels: &mut [[f64; 3]], prepared: &PreparedRender) {
    for pixel in pixels.iter_mut() {
        *pixel = prepared.render_pixel(*pixel);
    }
}

/// Render a whole image with grain.
///
/// The grain is an exposure fluctuation, so it is applied to the log exposure
/// and then pushed through the same curve — which is what keeps it out of a
/// blank frame and out of the shoulder without either case being special-cased.
pub fn render_pixels_with_grain(
    pixels: &mut [[f64; 3]],
    prepared: &PreparedRender,
    grain: &crate::grain::GrainField,
) {
    render_pixels_finished(
        pixels,
        prepared,
        grain.width,
        grain.height,
        &Finishing {
            halation: None,
            grain: Some(grain),
            couplers: None,
        },
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    fn chain(development: DevelopmentParams) -> PreparedRender {
        RenderParams {
            development,
            ..RenderParams::default()
        }
        .prepare()
    }

    #[test]
    fn print_balance_lands_mid_grey_on_target() {
        let prepared = chain(DevelopmentParams::default());
        let out = prepared.render_pixel([0.18, 0.18, 0.18]);
        for channel in out {
            assert!(
                (channel - 0.18).abs() < 0.005,
                "mid grey printed at {channel}"
            );
        }
    }

    /// Local slope of the whole chain, in density per decade of scene exposure,
    /// measured one stop either side of mid grey.
    fn local_contrast(prepared: &PreparedRender) -> f64 {
        let mid = 0.18;
        let low = prepared.render_pixel([mid / 2.0; 3])[1].max(1e-6);
        let high = prepared.render_pixel([mid * 2.0; 3])[1].max(1e-6);
        (high / low).log10() / 4.0_f64.log10()
    }

    #[test]
    fn over_development_raises_contrast() {
        let normal = local_contrast(&chain(DevelopmentParams::default()));
        let pushed = local_contrast(&chain(DevelopmentParams {
            time_min: 12.0,
            ..DevelopmentParams::default()
        }));
        assert!(pushed > normal, "normal {normal}, pushed {pushed}");
    }

    #[test]
    fn under_development_lowers_contrast() {
        let normal = local_contrast(&chain(DevelopmentParams::default()));
        let pulled = local_contrast(&chain(DevelopmentParams {
            time_min: 3.0,
            ..DevelopmentParams::default()
        }));
        assert!(pulled < normal, "normal {normal}, pulled {pulled}");
    }

    #[test]
    fn spectral_path_keeps_mid_grey_on_target() {
        let prepared = RenderParams {
            spectral: true,
            ..RenderParams::default()
        }
        .prepare();
        assert!(prepared.is_spectral());
        let out = prepared.render_pixel([0.18, 0.18, 0.18]);
        for channel in out {
            assert!(
                (channel - 0.18).abs() < 0.01,
                "mid grey printed at {channel}"
            );
        }
    }

    #[test]
    fn spectral_scan_produces_neutral_grey() {
        let prepared = RenderParams {
            spectral_print: true,
            spectral_scan: true,
            ..RenderParams::default()
        }
        .prepare();
        assert!(prepared.is_spectral_scan());

        let out = prepared.render_pixel([0.18, 0.18, 0.18]);
        let spread = out.iter().copied().fold(f64::NEG_INFINITY, f64::max)
            - out.iter().copied().fold(f64::INFINITY, f64::min);
        assert!(spread < 0.02, "grey drifts by {spread}: {out:?}");
        assert!(out[1] > 0.02 && out[1] < 0.6, "mid grey at {}", out[1]);
    }

    #[test]
    fn spectral_scan_is_monotonic_and_bounded() {
        let prepared = RenderParams {
            spectral_print: true,
            spectral_scan: true,
            ..RenderParams::default()
        }
        .prepare();
        let mut previous = -1.0;
        for i in -80..80 {
            let x = 2.0_f64.powf(f64::from(i) / 10.0) * 0.18;
            let y = prepared.render_pixel([x; 3])[1];
            assert!((0.0..=1.0).contains(&y));
            assert!(y >= previous - 1e-9, "non-monotonic at {x}");
            previous = y;
        }
    }

    #[test]
    fn spectral_print_keeps_mid_grey_on_target() {
        let prepared = RenderParams {
            spectral_print: true,
            ..RenderParams::default()
        }
        .prepare();
        assert!(prepared.is_spectral_print());
        let out = prepared.render_pixel([0.18, 0.18, 0.18]);
        for channel in out {
            assert!(
                (channel - 0.18).abs() < 0.01,
                "mid grey printed at {channel}"
            );
        }
    }

    #[test]
    fn spectral_print_couples_the_layers() {
        let scalar = RenderParams::default().prepare();
        let spectral = RenderParams {
            spectral_print: true,
            ..RenderParams::default()
        }
        .prepare();

        // A cyan-dominant patch: its density sits mostly in one channel, but the
        // dyes overlap, so the paper's other layers must move too.
        let sample = [0.08, 0.42, 0.45];
        let a = scalar.render_pixel(sample);
        let b = spectral.render_pixel(sample);
        let difference: f64 = a.iter().zip(&b).map(|(x, y)| (x - y).abs()).sum();
        assert!(difference > 1e-4, "no coupling visible: {difference}");
    }

    #[test]
    fn spectral_print_is_monotonic_and_bounded() {
        let prepared = RenderParams {
            spectral_print: true,
            ..RenderParams::default()
        }
        .prepare();
        let mut previous = -1.0;
        for i in -80..80 {
            let x = 2.0_f64.powf(f64::from(i) / 10.0) * 0.18;
            let y = prepared.render_pixel([x; 3])[1];
            assert!((0.0..=1.0).contains(&y));
            assert!(y >= previous - 1e-9, "non-monotonic at {x}");
            previous = y;
        }
    }

    #[test]
    fn the_baked_table_matches_the_live_path() {
        let live = RenderParams {
            spectral: true,
            ..RenderParams::default()
        }
        .prepare();
        let baked = RenderParams {
            spectral: true,
            lut_size: 33,
            ..RenderParams::default()
        }
        .prepare();
        assert!(baked.lut().is_some());
        assert!(live.lut().is_none());

        let mut worst = 0.0_f64;
        for r in 0..6 {
            for g in 0..6 {
                for b in 0..6 {
                    let rgb = [
                        0.02 + 0.16 * f64::from(r),
                        0.02 + 0.16 * f64::from(g),
                        0.02 + 0.16 * f64::from(b),
                    ];
                    let a = live.render_pixel(rgb);
                    let c = baked.render_pixel(rgb);
                    for channel in 0..3 {
                        worst = worst.max((a[channel] - c[channel]).abs());
                    }
                }
            }
        }
        // 0.05 reflectance is about the corner error of a 33^3 table; the
        // mean difference is two orders of magnitude smaller.
        assert!(worst < 0.05, "baked path differs by {worst}");
    }

    #[test]
    fn spectral_path_changes_colour_separation() {
        let scalar = RenderParams::default().prepare();
        let spectral = RenderParams {
            spectral: true,
            ..RenderParams::default()
        }
        .prepare();

        let sample = [0.75, 0.12, 0.08];
        let a = scalar.render_pixel(sample);
        let b = spectral.render_pixel(sample);
        let difference: f64 = a.iter().zip(&b).map(|(x, y)| (x - y).abs()).sum();
        assert!(
            difference > 1e-4,
            "spectral path changed nothing: {difference}"
        );
    }

    #[test]
    fn spectral_output_is_monotonic_and_bounded() {
        let prepared = RenderParams {
            spectral: true,
            ..RenderParams::default()
        }
        .prepare();
        let mut previous = -1.0;
        for i in -80..80 {
            let x = 2.0_f64.powf(f64::from(i) / 10.0) * 0.18;
            let y = prepared.render_pixel([x; 3])[1];
            assert!((0.0..=1.0).contains(&y));
            assert!(y >= previous - 1e-9, "non-monotonic at {x}");
            previous = y;
        }
    }

    #[test]
    fn output_is_monotonic_and_bounded() {
        let prepared = chain(DevelopmentParams::default());
        let mut previous = -1.0;
        for i in -80..80 {
            let x = 2.0_f64.powf(f64::from(i) / 10.0) * 0.18;
            let y = prepared.render_pixel([x; 3])[1];
            assert!((0.0..=1.0).contains(&y));
            assert!(y >= previous - 1e-9, "non-monotonic at {x}");
            previous = y;
        }
    }

    /// Grain has to be visible where the eye expects it: not in a flat black, not
    /// in a flat white, and unmistakably in between. Both ends are flat for a
    /// reason that is not written down anywhere — one characteristic curve is in
    /// its toe, the other in its shoulder.
    ///
    /// The peak is not at mid grey, and it should not be. Visible grain is the
    /// counting noise multiplied by the curve's local slope, and on a negative the
    /// straight line extends a couple of stops *above* mid grey, so the product
    /// peaks there. Measured with the measured stock, the spread runs 0.0003 at
    /// −8 EV, 0.0123 at 0, a peak of 0.0174 at +2, and 0.0004 by +8.
    #[test]
    fn grain_peaks_inside_the_straight_line() {
        const SIDE: usize = 64;
        let mut grain = crate::grain::GrainField::new(SIDE, SIDE, 36.0, 11);
        // A 6 µm pixel: a 6000-pixel scan of a 35 mm frame, where grain is real.
        grain.pixel_area_um2 = 36.0;

        let spread = |ev: f64| {
            let prepared = RenderParams {
                exposure_ev: ev,
                ..RenderParams::default()
            }
            .prepare();
            let mut pixels = vec![[0.18; 3]; SIDE * SIDE];
            render_pixels_with_grain(&mut pixels, &prepared, &grain);
            let mean = pixels.iter().map(|p| p[0]).sum::<f64>() / pixels.len() as f64;
            (pixels.iter().map(|p| (p[0] - mean).powi(2)).sum::<f64>() / pixels.len() as f64).sqrt()
        };

        let dark = spread(-8.0);
        let mid = spread(0.0);
        let peak = spread(2.0);
        let bright = spread(8.0);
        assert!(
            peak > 5.0 * dark && peak > 5.0 * bright,
            "peak {peak}  dark {dark}  bright {bright}"
        );
        assert!(
            peak > spread(-2.0) && peak > spread(6.0),
            "the peak is not in the middle: -2 {}, +2 {peak}, +6 {}",
            spread(-2.0),
            spread(6.0)
        );
        assert!(mid > 0.5 * peak, "mid {mid} against peak {peak}");
    }

    #[test]
    fn probe() {
        for (name, params) in [
            (
                "spectral",
                RenderParams {
                    spectral: true,
                    ..RenderParams::default()
                },
            ),
            (
                "print",
                RenderParams {
                    spectral_print: true,
                    ..RenderParams::default()
                },
            ),
            (
                "scan",
                RenderParams {
                    spectral_print: true,
                    spectral_scan: true,
                    ..RenderParams::default()
                },
            ),
        ] {
            let prepared = params.prepare();
            let model = prepared.spectral_model().expect(name);
            println!("== {name}");
            if let Some(e) = &model.exposure {
                println!("  reconstruct = {:?}", e.reconstruct);
                println!("  reference   = {:?}", e.reference);
                println!(
                    "  basis max   = {:?}",
                    [
                        e.basis[0].iter().fold(f64::MIN, |a, &b| a.max(b)),
                        e.basis[1].iter().fold(f64::MIN, |a, &b| a.max(b)),
                        e.basis[2].iter().fold(f64::MIN, |a, &b| a.max(b)),
                    ]
                );
                println!(
                    "  film max    = {:?}",
                    [
                        e.film[0].iter().fold(f64::MIN, |a, &b| a.max(b)),
                        e.film[1].iter().fold(f64::MIN, |a, &b| a.max(b)),
                        e.film[2].iter().fold(f64::MIN, |a, &b| a.max(b)),
                    ]
                );
            }
            if let Some(p) = &model.enlarger {
                println!("  analytical  = {:?}", p.analytical);
                println!(
                    "  clamped={} reference={:?} masking={:?} ref={}",
                    p.clamped, p.reference, p.masking, p.masking_reference
                );
                println!(
                    "  paper max   = {:?}",
                    [0, 1, 2].map(|c| p.paper[c].iter().fold(f64::MIN, |a, &b| a.max(b)))
                );
            }
            if let Some(s) = &model.scan {
                println!(
                    "  scan clamped={} white_xyz={:?} white_rgb={:?}",
                    s.clamped, s.white_xyz, s.white_rgb
                );
                println!(
                    "  neutral[0]={:?} neutral[32]={:?}",
                    s.neutral[0], s.neutral[32]
                );
            }
        }
    }
}
