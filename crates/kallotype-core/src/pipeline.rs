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

use crate::curve::{CharacteristicCurve, sigmoid};
use crate::development::DevelopmentParams;
use crate::emulsion::{FilmStock, PaperStock};
use crate::lut::ExposureLut;
use crate::spectral::SpectralContext;

/// log10 of the luminance a mid-grey card reflects. The anchor everything is
/// balanced against; 0.18 is the conventional value.
#[must_use]
pub fn mid_grey_log_e() -> f64 {
    0.18_f64.log10()
}

/// Everything needed to render: which film, which paper, and how it was developed.
#[derive(Debug, Clone, Copy)]
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
    /// Bake the spectral exposure into a `size^3` table. Zero disables it.
    pub lut_size: usize,
}

impl Default for RenderParams {
    fn default() -> Self {
        Self {
            film: crate::emulsion::film_stock("c41_standard").expect("built-in stock"),
            paper: crate::emulsion::paper_stock("c41_paper").expect("built-in stock"),
            development: DevelopmentParams::default(),
            exposure_ev: 0.0,
            spectral: false,
            lut_size: 0,
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
            ..*self
        }
        .prepare_with(None);
        prepared.lut = Some(lut);
        prepared
    }

    /// As [`Self::prepare`], with an optional dictionary for the spectral prior.
    ///
    /// The atoms are what the hybrid measured in `docs/0002-rgb-to-spectrum.md`
    /// needs; without them the spectral path uses the polynomial prior alone.
    #[must_use]
    pub fn prepare_with(&self, atoms: Option<&[kallotype_spectral::Spectrum]>) -> PreparedRender {
        let channels: [CharacteristicCurve; 3] =
            std::array::from_fn(|i| self.development.apply_to(self.film.channels[i]));

        let paper = self.paper.channel;
        let print_slope = paper.slope_factor();

        // Solve the enlarger exposure so that a mid-grey negative prints at
        // the paper's target reflectance. This is what an operator does with
        // the aperture and the test strip, done in closed form.
        let target_density = -self.paper.target_mid_reflectance.log10();
        let t_target = ((target_density - paper.d_min) / paper.span()).clamp(1e-4, 1.0 - 1e-4);
        let z_target = (t_target / (1.0 - t_target)).ln();

        let mid = mid_grey_log_e();
        let print_log_e0: [f64; 3] = std::array::from_fn(|i| {
            let density_mid = channels[i].density(mid);
            -density_mid - z_target / print_slope
        });

        PreparedRender {
            channels,
            paper,
            print_slope,
            print_log_e0,
            exposure_shift: self.exposure_ev * 2.0_f64.log10(),
            spectral: self
                .spectral
                .then(|| {
                    let context = SpectralContext::new();
                    match atoms {
                        Some(atoms) => context.with_atoms(atoms),
                        None => context,
                    }
                })
                .filter(|_| self.lut_size < 2),
            lut: (self.spectral && self.lut_size >= 2).then(|| {
                let context = SpectralContext::new();
                let context = match atoms {
                    Some(atoms) => context.with_atoms(atoms),
                    None => context,
                };
                ExposureLut::bake(self.lut_size, &context)
            }),
        }
    }
}

/// A [`RenderParams`] with the curves already developed and the print balanced.
#[derive(Debug, Clone)]
pub struct PreparedRender {
    channels: [CharacteristicCurve; 3],
    paper: CharacteristicCurve,
    print_slope: f64,
    print_log_e0: [f64; 3],
    exposure_shift: f64,
    /// The live spectral model, when no table was baked.
    spectral: Option<SpectralContext>,
    /// The baked table, when one was requested.
    lut: Option<ExposureLut>,
}

impl PreparedRender {
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

    /// The baked table, if one was requested.
    #[must_use]
    pub fn lut(&self) -> Option<&ExposureLut> {
        self.lut.as_ref()
    }

    /// Render one linear-light pixel.
    #[must_use]
    pub fn render_pixel(&self, linear: [f64; 3]) -> [f64; 3] {
        // Scalar path: the channel's own log exposure. Spectral path: the film's
        // three layers, each integrating a reconstructed spectrum. The fallback
        // keeps the function total; it cannot trigger with a context this module
        // built.
        let scalar = || std::array::from_fn(|channel| linear[channel].max(1e-10).log10());
        let log_e = if let Some(lut) = &self.lut {
            // Baked: three trilinear lookups.
            lut.sample(linear)
        } else if let Some(context) = &self.spectral {
            // Live: reconstruct and integrate.
            context.expose(linear).unwrap_or_else(scalar)
        } else {
            scalar()
        };

        let mut out = [0.0; 3];
        for channel in 0..3 {
            let log_e = log_e[channel] + self.exposure_shift;
            let density_negative = self.channels[channel].density(log_e);
            // The enlarger sees the light the negative transmitted.
            let log_transmittance = -density_negative;
            let z = self.print_slope * (log_transmittance - self.print_log_e0[channel]);
            let density_print = self.paper.d_min + self.paper.span() * sigmoid(z);
            out[channel] = 10.0_f64.powf(-density_print).clamp(0.0, 1.0);
        }
        out
    }
}

/// Render a whole image in place. Pixels are linear light on both sides.
pub fn render_pixels(pixels: &mut [[f64; 3]], prepared: &PreparedRender) {
    for pixel in pixels.iter_mut() {
        *pixel = prepared.render_pixel(*pixel);
    }
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
}
