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
    /// Run the cyan-sensitive layer's inhibitor (ADR 0018).
    ///
    /// Off by default, and only meaningful for a stock that declares such a
    /// layer: its strength and diffusion length are placeholders, so turning it
    /// on is asking for a demonstration of the mechanism, not for a prediction
    /// about the film.
    pub interimage: bool,
}

impl Default for RenderParams {
    fn default() -> Self {
        Self {
            film: crate::emulsion::film_stock("vision3_500t").expect("built-in stock"),
            paper: crate::emulsion::paper_stock("portra_endura").expect("built-in stock"),
            development: DevelopmentParams::default(),
            exposure_ev: 0.0,
            spectral: false,
            camera: CameraProfile::default(),
            lut_size: 0,
            spectral_print: false,
            spectral_scan: false,
            interimage: false,
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
        // A silver film has one record, so the three-channel scalar path cannot
        // express it: it would develop each input channel separately and print a
        // colour image from a film that has no colour. A monochrome stock is
        // therefore always exposed through its spectrum, whatever was asked for.
        let monochrome = self.film.process == crate::emulsion::FilmProcess::Monochrome;
        // ADR 0017: a dye fed by two emulsions is two integrals and two curves.
        // The scalar path has three numbers and one curve per channel, so it
        // cannot say a fourth layer exists; such a stock is always exposed
        // through its spectrum, exactly as a monochrome film is.
        let extra = self
            .film
            .extra_cyan
            .map(|emulsion| self.development.apply_to(emulsion.characteristic()));
        // A CL layer is a fourth integral too, and the scalar path has three
        // channels: it cannot even say that the layer exists.
        let cl_layer = self.interimage && self.film.cl_layer.is_some();
        let spectral = self.spectral || monochrome || extra.is_some() || cl_layer;
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
        let mut density_mid: [f64; 3] = std::array::from_fn(|i| channels[i].density(mid));
        // The cyan dye's second emulsion develops at mid grey too. Leaving it
        // out of this number would balance the enlarger on a negative the film
        // does not make, and every four-layer stock would print a stop dark in
        // cyan.
        if let Some(extra) = extra {
            density_mid[0] += extra.density(mid);
        }

        // Two ways to describe what reaches the paper. The scalar one treats each
        // density as that channel's light loss; the spectral one integrates the
        // dyes' absorption bands against the paper's layer sensitivities.
        let print = self.spectral_print.then(|| {
            PrintContext::measured_with(
                density_mid,
                self.film.dyes,
                self.film.mask,
                self.paper.layers,
            )
        });
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
            scan: self
                .spectral_scan
                .then(|| ScanContext::measured_with(self.paper.dyes)),
            extra,
            cl_layer,
            exposure_shift: self.exposure_ev * 2.0_f64.log10(),
            reversal: self.film.process == crate::emulsion::FilmProcess::Reversal,
            spectral: spectral
                .then(|| {
                    let context =
                        SpectralContext::for_stock(self.film).with_camera(self.camera.clone());
                    match atoms {
                        Some(atoms) => context.with_atoms(atoms),
                        None => context,
                    }
                })
                .filter(|_| self.lut_size < 2),
            lut: (spectral && self.lut_size >= 2 && extra.is_none()).then(|| {
                let context =
                    SpectralContext::for_stock(self.film).with_camera(self.camera.clone());
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
    /// How sharply each curve turns: the three layers, then the paper.
    ///
    /// It rides on the curve rather than on the model because it is a property
    /// of the material — see `crate::curve`.
    pub transition: [f64; 4],
    /// The film's minimum density in status terms: base, fog and mask.
    pub base_density: [f64; 3],
    /// The enlarger's exposure shift per layer, in decades.
    pub print_shift: [f64; 3],
    /// Exposure offset applied before the curve, in decades.
    pub exposure_shift: f64,
    /// Whether the film is its own picture. A reversal keeps its density and
    /// stops: there is no paper between the development and the eye.
    pub reversal: bool,
}

/// The exposure, as the curve stage receives it.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Exposure {
    /// Log exposure of the three layers, in the order the film records them.
    pub layers: [f64; 3],
    /// Log exposure of the cyan dye's second emulsion, when the stock has one.
    pub extra: Option<f64>,
}

/// A [`RenderParams`] with the curves already developed and the print balanced.
#[derive(Debug, Clone)]
pub struct PreparedRender {
    /// Whether the film is viewed directly rather than printed.
    pub reversal: bool,
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
    /// The cyan dye's second emulsion, when the stock has one — ADR 0017.
    ///
    /// Only its curve lives here. The sensitivity is a table the spectral
    /// context integrates, and the two meet in [`Self::negative_density_with`]:
    /// the context says how much light the layer saw, this says how much dye
    /// that made, and the cyan dye sums the two emulsions' densities.
    extra: Option<CharacteristicCurve>,
    /// Whether the fourth integral belongs to a cyan-sensitive inhibitor layer
    /// rather than to a dye-forming emulsion (ADR 0018).
    cl_layer: bool,
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
            transition: [
                self.channels[0].transition,
                self.channels[1].transition,
                self.channels[2].transition,
                self.paper.transition,
            ],
            base_density: self.base_density,
            print_shift: self.print_shift,
            exposure_shift: self.exposure_shift,
            reversal: self.reversal,
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
        // ADR 0017: the fourth layer is a fourth integral and a second curve on
        // the cyan dye. No field of the model carries it, and a backend that
        // replayed the three layers would render a different film without
        // saying so — so it declines, and the caller renders on the CPU.
        if self.extra.is_some() || self.cl_layer {
            return None;
        }
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

    /// Everything the curve stage needs from a pixel.
    ///
    /// The fourth layer rides beside the three rather than inside them: its
    /// density lands on the cyan dye, which already has a layer, so folding it
    /// into the blue channel's log exposure would combine the emulsions before
    /// their curves and lose exactly what ADR 0017 added.
    ///
    /// `None` for the fourth layer is the ordinary case — every stock before
    /// PRO 400H — and makes the rest of the chain the model it always was.
    pub fn expose(&self, linear: [f64; 3]) -> Exposure {
        let scalar = || std::array::from_fn(|channel| linear[channel].max(1e-10).log10());
        if let Some(lut) = &self.lut {
            // Baked: three trilinear lookups. A table cannot carry a fourth
            // axis, which is why `prepare_with` refuses one for such a stock.
            return Exposure {
                layers: lut.sample(linear),
                extra: None,
            };
        }
        if let Some(context) = &self.spectral {
            // Live: reconstruct once and integrate four times. The fallback
            // keeps the function total; it cannot trigger with a context this
            // module built.
            return match context.expose_with_extra(linear) {
                Some((layers, extra)) => Exposure { layers, extra },
                None => Exposure {
                    layers: scalar(),
                    extra: None,
                },
            };
        }
        Exposure {
            layers: scalar(),
            extra: None,
        }
    }

    /// The three log exposures: scalar per channel, or the film's layers
    /// integrating a reconstructed spectrum.
    #[must_use]
    pub fn log_exposure(&self, linear: [f64; 3]) -> [f64; 3] {
        self.expose(linear).layers
    }

    /// The negative's density, from log exposure.
    ///
    /// This is the three-layer model: one emulsion per dye. A stock with a
    /// fourth layer wants [`Self::negative_density_with`], which is this plus
    /// the second cyan emulsion.
    #[must_use]
    pub fn negative_density(&self, log_e: [f64; 3]) -> [f64; 3] {
        self.negative_density_with(log_e, None)
    }

    /// The negative's density, with the cyan dye's second emulsion when there
    /// is one.
    ///
    /// The sum is over densities: both emulsions make the same dye, and the
    /// densitometer sees one number, so two emulsions at half a stop each are
    /// not one at a stop. Ignoring `extra` is bit-for-bit the old model.
    #[must_use]
    pub fn negative_density_with(&self, log_e: [f64; 3], extra: Option<f64>) -> [f64; 3] {
        let mut density: [f64; 3] = std::array::from_fn(|channel| {
            self.channels[channel].density(log_e[channel] + self.exposure_shift)
        });
        if let (Some(curve), Some(log_e)) = (self.extra, extra) {
            density[0] += curve.density(log_e + self.exposure_shift);
        }
        density
    }

    /// The print and the scan, from the negative's density.
    #[must_use]
    pub fn positive(&self, density_cmy: [f64; 3]) -> [f64; 3] {
        // A reversal film is its own picture: there is no print, no paper and no
        // enlarger between the development and the eye. What leaves is what the
        // film transmits, and the density *is* the image.
        if self.reversal {
            // The film's clearest point is the projector's white: a slide's
            // density is absolute — 0.08 for clean film, 3.3 for unexposed —
            // and displaying it as a fraction of *clear film* rather than of
            // nothing is what a lamp behind it does. Without that the whole
            // image sits between two and eighty per cent and reads as a murk;
            // a projector's white level is not a correction, it is the other
            // half of the observation.
            return std::array::from_fn(|channel| {
                let white = self.channels[channel].d_max;
                10.0_f64
                    .powf(-(density_cmy[channel] + self.base_density[channel] - white))
                    .clamp(0.0, 1.0)
            });
        }

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
        linear: [f64; 3],
        x: usize,
        y: usize,
        grain: Option<&crate::grain::GrainField>,
    ) -> [f64; 3] {
        let exposure = self.expose(linear);
        let density = self.negative_density_with(exposure.layers, exposure.extra);
        let jittered: [f64; 3] = match grain {
            Some(grain) => std::array::from_fn(|channel| {
                exposure.layers[channel] + grain.jitter(x, y, density[channel], channel)
            }),
            None => exposure.layers,
        };
        self.positive(self.negative_density_with(jittered, exposure.extra))
    }

    /// Render one linear-light pixel.
    #[must_use]
    pub fn render_pixel(&self, linear: [f64; 3]) -> [f64; 3] {
        let exposure = self.expose(linear);
        self.positive(self.negative_density_with(exposure.layers, exposure.extra))
    }

    /// Whether the render carries a fourth layer of either kind.
    #[must_use]
    pub fn has_extra_layer(&self) -> bool {
        self.extra.is_some() || self.cl_layer
    }

    /// Whether the fourth layer releases inhibitor rather than forming dye.
    #[must_use]
    pub fn has_inhibitor_layer(&self) -> bool {
        self.cl_layer
    }
}

/// What happens between the exposure and the development.
///
/// Both are optional and independent; the model without them is the model.
#[derive(Debug, Clone, Copy, Default)]
pub struct Finishing<'a> {
    /// The film's own blur: how soft the emulsion makes everything.
    pub emulsion: Option<&'a crate::mtf::EmulsionBlur>,
    /// Light that scatters in the emulsion and reflects off the base.
    pub halation: Option<&'a crate::halation::Halation>,
    /// The emulsion's grain.
    pub grain: Option<&'a crate::grain::GrainField>,
    /// DIR couplers, acting on the developed densities.
    pub couplers: Option<&'a crate::couplers::Couplers>,
    /// The cyan-sensitive layer's inhibitor, acting on the cyan dye — ADR 0018.
    pub interimage: Option<&'a crate::interimage::InterImage>,
}

/// Run `f` over every pixel, in parallel when the `parallel` feature is on.
///
/// The render is embarrassingly parallel: a pixel's exposure, its density and
/// its print depend on that pixel alone. So this is the whole of the speed-up —
/// no tiling, no work queue, no second code path that could disagree with the
/// serial one. The spatial stages (halation, the couplers) run before and after
/// and stay serial, because they are the ones that genuinely look sideways.
#[inline]
fn each_pixel<T: Send>(data: &mut [T], width: usize, f: impl Fn(usize, usize, &mut T) + Sync) {
    #[cfg(feature = "parallel")]
    {
        use rayon::prelude::*;
        data.par_iter_mut()
            .enumerate()
            .for_each(|(index, slot)| f(index % width, index / width, slot));
    }
    #[cfg(not(feature = "parallel"))]
    {
        for (index, slot) in data.iter_mut().enumerate() {
            f(index % width, index / width, slot);
        }
    }
}

/// [`each_pixel`], for two planes that describe the same pixel.
///
/// The fourth layer needs a plane of its own — it is a layer, not a fourth
/// number in a three-channel pixel — and its exposure comes from the same
/// reconstructed spectrum as the other three. Filling the two in separate
/// passes would reconstruct every spectrum twice.
#[inline]
fn each_pixel_pair<A: Send, B: Send>(
    first: &mut [A],
    second: &mut [B],
    width: usize,
    f: impl Fn(usize, usize, &mut A, &mut B) + Sync,
) {
    #[cfg(feature = "parallel")]
    {
        use rayon::prelude::*;
        first
            .par_iter_mut()
            .zip(second.par_iter_mut())
            .enumerate()
            .for_each(|(index, (left, right))| f(index % width, index / width, left, right));
    }
    #[cfg(not(feature = "parallel"))]
    {
        for (index, (left, right)) in first.iter_mut().zip(second.iter_mut()).enumerate() {
            f(index % width, index / width, left, right);
        }
    }
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
    if finishing.emulsion.is_none()
        && finishing.halation.is_none()
        && finishing.couplers.is_none()
        && finishing.interimage.is_none()
    {
        each_pixel(pixels, width, |x, y, pixel| {
            *pixel = prepared.finish(*pixel, x, y, finishing.grain);
        });
        return;
    }

    // Exposure first: halation moves light between pixels, before anything is
    // developed.
    let mut log_e: Vec<[f64; 3]> = pixels.to_vec();
    // The fourth layer is a fourth plane, allocated only when the stock has
    // one: a stock without it renders through exactly the vectors it used to.
    let mut extra: Option<Vec<f64>> = prepared.has_extra_layer().then(|| vec![0.0; log_e.len()]);
    match extra.as_mut() {
        Some(plane) => each_pixel_pair(&mut log_e, plane, width, |_, _, pixel, slot| {
            let exposure = prepared.expose(*pixel);
            *pixel = exposure.layers;
            // No integral means no exposure: the emulsion stays at its
            // minimum density rather than at a plausible-looking zero.
            *slot = exposure.extra.unwrap_or(f64::NEG_INFINITY);
        }),
        None => each_pixel(&mut log_e, width, |_, _, pixel| {
            *pixel = prepared.log_exposure(*pixel);
        }),
    }
    // The emulsion's own blur comes first: it is the lens's image being
    // softened by the film, and the halo is light that entered the film and
    // came back, so it is distributed by the same blur afterwards.
    if let Some(emulsion) = finishing.emulsion {
        emulsion.apply(&mut log_e, width, height);
    }
    if let Some(halation) = finishing.halation {
        halation.apply(&mut log_e, width, height);
    }

    // Then the emulsion: grain on the exposure, the curve on the result.
    let mut density: Vec<[f64; 3]> = log_e.clone();
    each_pixel(&mut density, width, |x, y, slot| {
        let log_e = log_e[y * width + x];
        let extra = extra.as_ref().map(|plane| plane[y * width + x]);
        let mean = prepared.negative_density_with(log_e, extra);
        *slot = match finishing.grain {
            Some(grain) => prepared.negative_density_with(
                std::array::from_fn(|channel| {
                    log_e[channel] + grain.jitter(x, y, mean[channel], channel)
                }),
                extra,
            ),
            None => mean,
        };
    });

    // The cyan-sensitive layer's inhibitor, before the couplers: its release is
    // the light the layer absorbed, not the density it developed, so it is the
    // earlier of the two development effects.
    if let (Some(stage), Some(plane)) = (finishing.interimage, extra.as_ref()) {
        let light: Vec<f64> = plane.iter().map(|value| 10f64.powf(*value)).collect();
        stage.apply(&mut density, &light, width, height);
    }

    // Then the chemistry: the inhibitors act on what has already developed.
    if let Some(couplers) = finishing.couplers {
        couplers.apply(&mut density, width, height);
    }

    each_pixel(pixels, width, |x, y, pixel| {
        *pixel = prepared.positive(density[y * width + x]);
    });
}

/// Render a whole image in place.
pub fn render_pixels(pixels: &mut [[f64; 3]], prepared: &PreparedRender) {
    // Width only matters to the grain, which this path has none of.
    each_pixel(pixels, 1, |_, _, pixel| {
        *pixel = prepared.render_pixel(*pixel);
    });
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
            emulsion: None,
            halation: None,
            grain: Some(grain),
            couplers: None,
            interimage: None,
        },
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The fourth layer's sensitivity: a straight line at 5 nm, sampled every
    /// 10 nm. Interpolating it back onto the model grid returns the same
    /// function, so it sees *exactly* what the blue layer sees and only the
    /// anchor can differ.
    const STRAIGHT: [f32; 36] = {
        let mut table = [0.0_f32; 36];
        let mut index = 0;
        while index < 36 {
            table[index] = 1.0 + 0.02 * (index as f32);
            index += 1;
        }
        table
    };

    /// A four-layer stock: three identical straight-line layers and a cyan dye
    /// fed by a second emulsion. `Box::leak` because [`RenderParams`] borrows
    /// the stock and the test is its only owner.
    fn four_layer(curve: [f64; 4]) -> &'static FilmStock {
        let mut straight = [0.0; crate::spectral::GRID_LEN];
        for (index, value) in straight.iter_mut().enumerate() {
            *value = 1.0 + 0.01 * index as f64;
        }
        let layers: &'static [[f64; crate::spectral::GRID_LEN]; 3] =
            Box::leak(Box::new([straight, straight, straight]));
        let mut stock = *crate::emulsion::film_stock("vision3_500t").expect("built-in stock");
        stock.id = "test_four_layer";
        stock.layers = layers;
        stock.extra_cyan = Some(crate::dye::Emulsion {
            curve,
            transition: crate::curve::TRANSITION,
            sensitivity: &STRAIGHT,
        });
        Box::leak(Box::new(stock))
    }

    /// The fourth layer's plane has to survive the effects path too: it is
    /// filled beside the three-channel exposure, developed by the same curve
    /// pass, and read back as the cyan dye's second density. A stock without a
    /// fourth layer never allocates it, which is why this is the only test that
    /// takes the pair path with a non-empty plane.
    #[test]
    fn a_four_layer_frame_renders_through_the_effects_path() {
        let prepared = RenderParams {
            film: four_layer([0.0, 1.0, 1.0, -0.5]),
            ..RenderParams::default()
        }
        .prepare();
        assert!(prepared.has_extra_layer());

        let mut pixels = vec![
            [0.6, 0.3, 0.1],
            [0.1, 0.2, 0.4],
            [0.05, 0.05, 0.05],
            [0.9, 0.9, 0.9],
        ];
        let halation = crate::halation::Halation::typical(6.0);
        render_pixels_finished(
            &mut pixels,
            &prepared,
            2,
            2,
            &Finishing {
                emulsion: None,
                halation: Some(&halation),
                grain: None,
                couplers: None,
                interimage: None,
            },
        );
        assert!(
            pixels
                .iter()
                .all(|pixel| pixel.iter().all(|value| value.is_finite() && *value >= 0.0))
        );

        // The same frame through the no-effects path: the two differ only by
        // the halo, which is small but not nothing on a bright edge.
        let mut plain = vec![
            [0.6, 0.3, 0.1],
            [0.1, 0.2, 0.4],
            [0.05, 0.05, 0.05],
            [0.9, 0.9, 0.9],
        ];
        render_pixels_finished(
            &mut plain,
            &prepared,
            2,
            2,
            &Finishing {
                emulsion: None,
                halation: None,
                grain: None,
                couplers: None,
                interimage: None,
            },
        );
        for (halated, plain) in pixels.iter().zip(&plain) {
            for (left, right) in halated.iter().zip(plain) {
                assert!((left - right).abs() < 0.5, "{halated:?} vs {plain:?}");
            }
        }
    }

    /// The enlarger is balanced on the density the negative actually has, so a
    /// four-layer stock must still print mid grey as mid grey. If the balance
    /// ignored the second emulsion, the printed grey would come out too dark in
    /// cyan by exactly that density.
    #[test]
    fn a_four_layer_stock_still_prints_mid_grey_as_mid_grey() {
        for curve in [[0.0, 1.0, 1.0, -1.0], [0.0, 2.0, 0.7, -0.2]] {
            let prepared = RenderParams {
                film: four_layer(curve),
                ..RenderParams::default()
            }
            .prepare();
            let exposure = prepared.expose([0.18, 0.18, 0.18]);
            let printed =
                prepared.positive(prepared.negative_density_with(exposure.layers, exposure.extra));
            for value in printed {
                assert!(
                    (value - 0.18).abs() < 0.02,
                    "curve {curve:?} printed {printed:?}"
                );
            }
        }
    }

    /// A stock with a cyan-sensitive inhibitor layer and no dye-forming fourth
    /// emulsion: the arrangement ADR 0018 exists for.
    fn inhibitor_stock() -> &'static FilmStock {
        static SENSITIVITY: [f64; crate::spectral::GRID_LEN] = [1.0; crate::spectral::GRID_LEN];
        let mut stock = *crate::emulsion::film_stock("vision3_500t").expect("built-in stock");
        stock.id = "test_inhibitor_layer";
        stock.cl_layer = Some(crate::dye::InhibitorLayer {
            sensitivity: &SENSITIVITY,
        });
        Box::leak(Box::new(stock))
    }

    /// ADR 0018: the layer shows where the frame has structure, and only in the
    /// cyan channel. A stock with such a layer renders identically until the
    /// stage is asked for, which is what keeps PRO 400H a three-layer stock on
    /// the GPU by default.
    #[test]
    fn the_inhibitor_layer_shows_only_where_the_frame_has_structure() {
        let off = RenderParams {
            film: inhibitor_stock(),
            ..RenderParams::default()
        }
        .prepare();
        let on = RenderParams {
            film: inhibitor_stock(),
            interimage: true,
            ..RenderParams::default()
        }
        .prepare();
        assert!(!off.has_inhibitor_layer());
        assert!(on.has_inhibitor_layer());
        // The fourth integral is a quantity the replayable model has no lane
        // for, so a backend declines whenever the layer is in the render.
        assert!(on.spectral_model().is_none());
        assert!(off.scalar_model().is_some());

        let stage = crate::interimage::InterImage::typical(6.0);
        let finishing = |interimage| Finishing {
            emulsion: None,
            halation: None,
            grain: None,
            couplers: None,
            interimage,
        };
        // Sixty-four pixels: thirty-two warm, thirty-two cool. Both renders use
        // the same prepared render — same exposure, same curve, same print — so
        // the only thing that differs is whether the inhibitor acted.
        let mut pixels = Vec::new();
        for index in 0..64 {
            pixels.push(if index < 32 {
                [0.9, 0.2, 0.1]
            } else {
                [0.1, 0.2, 0.9]
            });
        }
        let mut with = pixels.clone();
        let mut without = pixels;
        render_pixels_finished(&mut with, &on, 64, 1, &finishing(Some(&stage)));
        render_pixels_finished(&mut without, &on, 64, 1, &finishing(None));

        // Which half the layer sees more of is the exposure's answer, not the
        // eye's: a flat sensitivity integrates the reconstructed spectrum, and
        // a warm RGB triple is not the brighter one in it. So the expectation
        // comes from the render's own fourth integral.
        let warm = on
            .expose([0.9, 0.2, 0.1])
            .extra
            .expect("the layer is in the render");
        let cool = on
            .expose([0.1, 0.2, 0.9])
            .extra
            .expect("the layer is in the render");
        // The two pixels either side of the boundary: the brighter one is the
        // side whose inhibitor diffuses away, the shadow is the side that
        // receives it.
        let (bright, shadow) = if warm > cool { (31, 32) } else { (32, 31) };

        // The sign of the *print* is not the sign of the *density*: the
        // inhibitor takes cyan density off the negative, and a negative with
        // less cyan passes more red light, which the paper then develops into
        // more cyan. So the shadow keeps less red than it would have, and the
        // bright side keeps more.
        assert!(
            with[shadow][0] < without[shadow][0],
            "the shadow did not lose cyan: {:?} vs {:?}",
            with[shadow],
            without[shadow]
        );
        assert!(
            with[bright][0] > without[bright][0],
            "the bright side did not gain: {:?} vs {:?}",
            with[bright],
            without[bright]
        );
        // The other two dyes are not this layer's business.
        for (left, right) in with.iter().zip(&without) {
            assert!((left[1] - right[1]).abs() < 1e-12);
            assert!((left[2] - right[2]).abs() < 1e-12);
        }
    }

    /// ADR 0017's compatibility promise: the eighteen stocks that were here
    /// before the fourth layer exist are still the three-layer model, bit for
    /// bit, and a backend can still replay every one of them.
    #[test]
    fn a_stock_without_a_fourth_layer_is_still_the_three_layer_model() {
        for stock in crate::emulsion::FILM_STOCKS {
            let prepared = RenderParams {
                film: stock,
                ..RenderParams::default()
            }
            .prepare();
            assert!(!prepared.has_extra_layer(), "{}", stock.id);

            let pixel = [0.4, 0.3, 0.2];
            let exposure = prepared.expose(pixel);
            assert_eq!(exposure.extra, None, "{}", stock.id);
            let expected: [f64; 3] = std::array::from_fn(|channel| {
                prepared.channels()[channel].density(exposure.layers[channel])
            });
            assert_eq!(
                prepared.negative_density(exposure.layers),
                expected,
                "{}",
                stock.id
            );
            // Still exactly one of the two replayable models: nothing about a
            // three-layer stock newly declines the GPU.
            assert!(
                prepared.scalar_model().is_some() || prepared.spectral_model().is_some(),
                "{}",
                stock.id
            );
        }
    }

    /// The fourth layer is a density on the cyan dye, not a fourth exposure.
    #[test]
    fn a_second_emulsion_adds_density_on_the_cyan_dye() {
        let curve = [0.05, 1.2, 0.7, -1.0];
        let prepared = RenderParams {
            film: four_layer(curve),
            ..RenderParams::default()
        }
        .prepare();

        assert!(prepared.has_extra_layer());
        // A second emulsion is a fourth integral and a second curve: the
        // scalar path cannot say it, and the spectral model has no lane for
        // it, so a backend has to decline rather than replay three layers.
        assert!(prepared.is_spectral());
        assert!(prepared.scalar_model().is_none());
        assert!(prepared.spectral_model().is_none());

        let exposure = prepared.expose([0.4, 0.3, 0.2]);
        let extra = exposure.extra.expect("the stock has a second emulsion");
        let added = crate::curve::density_from(
            curve[0],
            curve[1],
            curve[2],
            curve[3],
            crate::curve::TRANSITION,
            extra,
        );

        let without = prepared.negative_density_with(exposure.layers, None);
        let with = prepared.negative_density_with(exposure.layers, Some(extra));
        assert!(
            (with[0] - without[0] - added).abs() < 1e-12,
            "cyan: {} + {added} vs {}",
            without[0],
            with[0]
        );
        // The other two dyes are untouched: the layer shares a dye, not a
        // channel.
        assert_eq!([with[1], with[2]], [without[1], without[2]]);
    }

    /// The fourth layer is normalised on the **blue** layer's grey response,
    /// not on its own. The data sheet plots all four emulsions on one log H
    /// axis, and the distance between the blue-sensitive curve and the
    /// cyan-sensitive one is a speed difference that self-anchoring would
    /// divide out.
    ///
    /// With a sensitivity that is the blue layer's own function, the two
    /// integrals must agree to the last digit at every colour — including the
    /// ones where mid grey's exposure, −0.744, is nowhere near.
    #[test]
    fn the_fourth_layer_is_anchored_on_the_blue_layer() {
        let prepared = RenderParams {
            film: four_layer([0.0, 1.0, 1.0, 0.0]),
            ..RenderParams::default()
        }
        .prepare();
        for pixel in [[0.18, 0.18, 0.18], [0.9, 0.1, 0.05], [0.05, 0.2, 0.8]] {
            let exposure = prepared.expose(pixel);
            let extra = exposure.extra.expect("the stock has a second emulsion");
            let blue = exposure.layers[2];
            assert!(
                (extra - blue).abs() < 1e-6,
                "{pixel:?}: fourth layer {extra} vs blue layer {blue}"
            );
        }
    }

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

    #[test]
    fn a_reversal_film_is_not_printed() {
        // The only stage that separates a reversal from a negative is the print:
        // the film's own density is the picture, so what leaves is its
        // transmittance and not a paper's response to it. The white point is the
        // film's clearest density — a projector's lamp, not the absence of film.
        let stock = crate::emulsion::film_stock("provia_100f").expect("the reversal stock");
        let prepared = RenderParams {
            film: stock,
            ..RenderParams::default()
        }
        .prepare();
        assert!(prepared.reversal);

        let density = [1.0, 1.5, 2.0];
        let out = prepared.positive(density);
        for channel in 0..3 {
            let white = prepared.channels()[channel].d_max;
            let expected =
                10.0_f64.powf(-(density[channel] + prepared.base_density[channel] - white));
            assert!(
                (out[channel] - expected).abs() < 1e-12,
                "channel {channel}: {} against {expected}",
                out[channel]
            );
        }

        // And the ends behave: unexposed film is black, clear film is white.
        let black = prepared.render_pixel([0.0; 3]);
        let clear = prepared.render_pixel([4.0; 3]);
        for channel in 0..3 {
            assert!(black[channel] < 0.01, "unexposed at {}", black[channel]);
            assert!(clear[channel] > 0.9, "fully exposed at {}", clear[channel]);
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
