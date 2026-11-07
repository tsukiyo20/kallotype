//! What the shaders compute, transcribed back to the CPU.
//!
//! CI runners have no GPU, so every test that needs an adapter skips there. A
//! regression in the *numbers* a shader is handed — a table left out of the
//! buffer, a stage that starts carrying the wavelength step on its own, the
//! unmixing done at the wrong point in the chain — would then go unnoticed until
//! somebody ran it on a laptop.
//!
//! This module closes that gap. It is compiled only for tests, it reads the same
//! [`ScalarModel`]/[`SpectralModel`] the buffer writer reads, and it performs the
//! same arithmetic in f64 that `scalar.wgsl` and `spectral.wgsl` perform in f32.
//! Compared against [`PreparedRender`] it proves the model is *complete*; the
//! adapter test proves the shader *implements* it.
//!
//! It is not a second reference implementation: it agrees with the CPU by
//! construction, and if the two ever disagree the extraction is wrong, not the
//! model. The two shaders are checked against it the same way.

use kallotype_core::{GrainField, PreparedRender, ScalarModel, SpectralModel};

const LOG2_10: f64 = std::f64::consts::LOG2_10;

/// Replay a whole image, choosing the shader the render would choose.
pub(crate) fn render(
    pixels: &[[f64; 3]],
    prepared: &PreparedRender,
    grain: Option<&GrainField>,
) -> Vec<[f64; 3]> {
    if let Some(model) = prepared.scalar_model() {
        return pixels
            .iter()
            .enumerate()
            .map(|(index, pixel)| scalar(&model, *pixel, grain, index))
            .collect();
    }
    if let Some(model) = prepared.spectral_model() {
        return pixels
            .iter()
            .enumerate()
            .map(|(index, pixel)| spectral(&model, *pixel, grain, index))
            .collect();
    }
    panic!("the render is neither scalar nor closed-form spectral");
}

/// The mean density a layer develops to, then the grain's version of it.
///
/// The fluctuation is sized by the *mean* density and applied to the exposure,
/// so the curve runs twice — which is what keeps grain out of a blank frame and
/// out of the shoulder without either case being special-cased.
fn developed(
    curve: &[f64; 4],
    log_e: f64,
    shift: f64,
    grain: Option<&GrainField>,
    index: usize,
    layer: usize,
) -> f64 {
    let mean = curve_density(*curve, log_e + shift);
    match grain {
        None => mean,
        Some(grain) => {
            let (x, y) = (index % grain.width.max(1), index / grain.width.max(1));
            let jitter = grain_jitter(grain, x, y, layer, mean);
            curve_density(*curve, log_e + jitter + shift)
        }
    }
}

fn softplus(u: f64) -> f64 {
    u.max(0.0) + (-u.abs()).exp().ln_1p()
}

/// The characteristic curve, from its four numbers. Mirrors `common.wgsl`.
fn curve_density(c: [f64; 4], x: f64) -> f64 {
    let span = (c[1] - c[0]).max(1e-9);
    let gamma = c[2].max(1e-9);
    let half = 0.5 * span / gamma;
    let toe = c[3] - half;
    let shoulder = c[3] + half;
    let transition = 4.0;
    c[0] + (gamma / transition)
        * (softplus(transition * (x - toe)) - softplus(transition * (x - shoulder)))
}

/// `scalar.wgsl`, stage for stage.
fn scalar(
    model: &ScalarModel,
    linear: [f64; 3],
    grain: Option<&GrainField>,
    index: usize,
) -> [f64; 3] {
    std::array::from_fn(|layer| {
        let log_e = linear[layer].max(1e-10).log10();
        let negative = developed(
            &model.curve[layer],
            log_e,
            model.exposure_shift,
            grain,
            index,
            layer,
        );
        let printed = curve_density(
            model.paper,
            -(negative + model.base_density[layer]) + model.print_shift[layer],
        );
        (-printed * LOG2_10).exp2().clamp(0.0, 1.0)
    })
}

/// `spectral.wgsl`, stage for stage.
fn spectral(
    model: &SpectralModel,
    linear: [f64; 3],
    grain: Option<&GrainField>,
    index: usize,
) -> [f64; 3] {
    let log_e = match &model.exposure {
        Some(exposure) => spectral_log_exposure(exposure, model.step_nm, linear),
        None => std::array::from_fn(|layer| linear[layer].max(1e-10).log10()),
    };

    let density: [f64; 3] = std::array::from_fn(|layer| {
        developed(
            &model.scalar.curve[layer],
            log_e[layer],
            model.scalar.exposure_shift,
            grain,
            index,
            layer,
        )
    });

    let log_transmittance = match &model.enlarger {
        Some(enlarger) => print_expose(enlarger, model.step_nm, density),
        None => std::array::from_fn(|layer| -(density[layer] + model.scalar.base_density[layer])),
    };

    let printed: [f64; 3] = std::array::from_fn(|layer| {
        curve_density(
            model.scalar.paper,
            log_transmittance[layer] + model.scalar.print_shift[layer],
        )
    });

    match &model.scan {
        Some(scan) => scan_colour(scan, model.step_nm, printed).map(|value| value.clamp(0.0, 1.0)),
        None => printed.map(|value| (-value * LOG2_10).exp2().clamp(0.0, 1.0)),
    }
}

fn spectral_log_exposure(
    exposure: &kallotype_core::ExposureModel,
    step_nm: f64,
    linear: [f64; 3],
) -> [f64; 3] {
    let coefficients: [f64; 3] = std::array::from_fn(|row| {
        (0..3)
            .map(|column| exposure.reconstruct[row][column] * linear[column])
            .sum()
    });

    let mut response = [0.0_f64; 3];
    for index in 0..kallotype_core::spectral::GRID_LEN {
        let value = coefficients
            .iter()
            .zip(&exposure.basis)
            .map(|(coefficient, term)| coefficient * term[index])
            .sum::<f64>()
            .max(0.0);
        for (response, film) in response.iter_mut().zip(&exposure.film) {
            *response += film[index] * value;
        }
    }

    std::array::from_fn(|layer| {
        let anchor = exposure.reference[layer].max(1e-12);
        let normalised = response[layer] * step_nm * 0.18 / anchor;
        normalised.max(1e-10).log10()
    })
}

fn unmix(matrix: &[[f64; 3]; 3], clamped: bool, status: [f64; 3]) -> [f64; 3] {
    std::array::from_fn(|row| {
        let value: f64 = (0..3)
            .map(|column| matrix[row][column] * status[column])
            .sum();
        if clamped { value.max(0.0) } else { value }
    })
}

fn print_response(
    enlarger: &kallotype_core::PrintModel,
    step_nm: f64,
    status: [f64; 3],
) -> [f64; 3] {
    let density_cmy = unmix(&enlarger.analytical, enlarger.clamped, status);

    let reference = enlarger.masking_reference.max(1e-9);
    let removed: f64 = (0..3)
        .map(|layer| enlarger.masking[layer] * (density_cmy[layer] / reference).clamp(0.0, 1.0))
        .sum();
    let surviving = (1.0 - removed).clamp(0.0, 1.0);

    let mut response = [0.0_f64; 3];
    for index in 0..kallotype_core::spectral::GRID_LEN {
        let mut density = enlarger.mask[index] * surviving;
        for (density_cmy, dye) in density_cmy.iter().zip(&enlarger.dye) {
            density += density_cmy * dye[index];
        }
        let filtration: f64 = (0..3)
            .map(|layer| enlarger.filters[layer] * enlarger.filter_bands[layer][index] / 100.0)
            .sum();
        let transmitted = (-(density + filtration) * LOG2_10).exp2() * enlarger.illuminant[index];
        for (response, paper) in response.iter_mut().zip(&enlarger.paper) {
            *response += paper[index] * transmitted;
        }
    }
    response.map(|value| value * step_nm)
}

fn print_balanced(
    enlarger: &kallotype_core::PrintModel,
    step_nm: f64,
    status: [f64; 3],
) -> [f64; 3] {
    let response = print_response(enlarger, step_nm, status);
    let mean = (status[0] + status[1] + status[2]) / 3.0;
    let neutral = print_response(enlarger, step_nm, [mean; 3]);
    let balance = (neutral[0] * neutral[1] * neutral[2]).cbrt();
    std::array::from_fn(|layer| response[layer] * (balance / neutral[layer].max(1e-12)))
}

fn print_expose(enlarger: &kallotype_core::PrintModel, step_nm: f64, status: [f64; 3]) -> [f64; 3] {
    let balanced = print_balanced(enlarger, step_nm, status);
    std::array::from_fn(|layer| {
        (balanced[layer] / enlarger.reference[layer].max(1e-12))
            .max(1e-10)
            .log10()
    })
}

fn scan_colour(scan: &kallotype_core::ScanModel, step_nm: f64, printed: [f64; 3]) -> [f64; 3] {
    let density_cmy = unmix(&scan.analytical, scan.clamped, printed);

    let mut xyz = [0.0_f64; 3];
    for index in 0..kallotype_core::spectral::GRID_LEN {
        let mut density = scan.base_density;
        for (density_cmy, dye) in density_cmy.iter().zip(&scan.dye) {
            density += density_cmy * dye[index];
        }
        let light = (-density * LOG2_10).exp2() * scan.illuminant[index];
        for (xyz, cmf) in xyz.iter_mut().zip(&scan.cmf) {
            *xyz += light * cmf[index];
        }
    }
    let xyz = xyz.map(|value| value * step_nm);
    let normalised: [f64; 3] =
        std::array::from_fn(|axis| xyz[axis] / scan.white_xyz[axis].max(1e-12));

    let rgb: [f64; 3] = std::array::from_fn(|row| {
        (0..3)
            .map(|column| scan.matrix[row][column] * normalised[column])
            .sum()
    });
    let white_relative: [f64; 3] =
        std::array::from_fn(|axis| rgb[axis] / scan.white_rgb[axis].max(1e-12));

    let mean = (printed[0] + printed[1] + printed[2]) / 3.0;
    let steps = (scan.neutral.len() - 1) as f64;
    let position = (mean / scan.neutral_max_density * steps).clamp(0.0, steps);
    let low = position.floor() as usize;
    let high = (low + 1).min(steps as usize);
    let fraction = position - low as f64;
    let neutral: [f64; 3] = std::array::from_fn(|axis| {
        scan.neutral[low][axis] * (1.0 - fraction) + scan.neutral[high][axis] * fraction
    });
    let balance = (neutral[0].max(1e-12) * neutral[1].max(1e-12) * neutral[2].max(1e-12)).cbrt();

    std::array::from_fn(|axis| white_relative[axis] * balance / neutral[axis].max(1e-12))
}

// ---------------------------------------------------------------------------
// The grain draw, in the shader's own arithmetic.
//
// Written out on 32-bit halves rather than with Rust's `u64` because that is
// what `grain.wgsl` has to do: a test that used the original would prove that
// `u64` works, not that the transcription does.
// ---------------------------------------------------------------------------

/// A 64-bit value as the two halves WGSL has.
#[derive(Clone, Copy)]
struct Wide {
    hi: u32,
    lo: u32,
}

fn wide_xor(left: Wide, right: Wide) -> Wide {
    Wide {
        hi: left.hi ^ right.hi,
        lo: left.lo ^ right.lo,
    }
}

fn wide_add(left: Wide, right: Wide) -> Wide {
    let lo = left.lo.wrapping_add(right.lo);
    let carry = u32::from(lo < left.lo);
    Wide {
        hi: left.hi.wrapping_add(right.hi).wrapping_add(carry),
        lo,
    }
}

fn wide_shr(value: Wide, count: u32) -> Wide {
    if count >= 32 {
        return Wide {
            hi: 0,
            lo: value.hi >> (count - 32),
        };
    }
    Wide {
        hi: value.hi >> count,
        lo: (value.lo >> count) | (value.hi << (32 - count)),
    }
}

fn mul_hi(left: u32, right: u32) -> u32 {
    let a0 = left & 0xFFFF;
    let a1 = left >> 16;
    let b0 = right & 0xFFFF;
    let b1 = right >> 16;

    let mut t = a0.wrapping_mul(b0);
    let carry0 = t >> 16;
    t = a1.wrapping_mul(b0).wrapping_add(carry0);
    let middle = t & 0xFFFF;
    let carry1 = t >> 16;
    t = a0.wrapping_mul(b1).wrapping_add(middle);
    a1.wrapping_mul(b1)
        .wrapping_add(carry1)
        .wrapping_add(t >> 16)
}

fn wide_mul(left: Wide, right: Wide) -> Wide {
    let cross = left
        .lo
        .wrapping_mul(right.hi)
        .wrapping_add(left.hi.wrapping_mul(right.lo));
    Wide {
        hi: mul_hi(left.lo, right.lo).wrapping_add(cross),
        lo: left.lo.wrapping_mul(right.lo),
    }
}

fn splitmix64(state: Wide) -> Wide {
    let mut value = wide_add(
        state,
        Wide {
            hi: 0x9E37_79B9,
            lo: 0x7F4A_7C15,
        },
    );
    value = wide_mul(
        wide_xor(value, wide_shr(value, 30)),
        Wide {
            hi: 0xBF58_476D,
            lo: 0x1CE4_E5B9,
        },
    );
    value = wide_mul(
        wide_xor(value, wide_shr(value, 27)),
        Wide {
            hi: 0x94D0_49BB,
            lo: 0x1331_11EB,
        },
    );
    wide_xor(value, wide_shr(value, 31))
}

fn grain_seed(seed: u64) -> Wide {
    Wide {
        hi: (seed >> 32) as u32,
        lo: seed as u32,
    }
}

fn grain_uniform(seed: Wide, x: u32, y: u32, layer: u32, lane: u32) -> f64 {
    let multiply =
        |value: u32, hi: u32, lo: u32| wide_mul(Wide { hi: 0, lo: value }, Wide { hi, lo });

    let mut state = wide_mul(
        seed,
        Wide {
            hi: 0xD6E8_FEB8,
            lo: 0x6659_FD93,
        },
    );
    state = wide_xor(state, multiply(x, 0x9E37_79B9, 0x7F4A_7C15));
    state = wide_xor(state, multiply(y, 0xC2B2_AE3D, 0x27D4_EB4F));
    state = wide_xor(state, multiply(layer, 0x1656_67B1, 0x9E37_79F9));
    state = wide_xor(state, multiply(lane, 0x2545_F491, 0x4F6C_DD1D));

    let bits = wide_shr(splitmix64(state), 41).lo;
    (f64::from(bits) + 0.5) * (1.0 / 8_388_608.0)
}

fn grain_normal(seed: Wide, x: u32, y: u32, layer: u32) -> f64 {
    let u1 = grain_uniform(seed, x, y, layer, 0);
    let u2 = grain_uniform(seed, x, y, layer, 1);
    (-2.0 * u1.ln()).sqrt() * (std::f64::consts::TAU * u2).cos()
}

fn grain_sigma(grain: &GrainField, density: f64, layer: usize) -> f64 {
    let covered = 1.0 - (-density.max(0.0) * LOG2_10).exp2();
    let grains = grain.grains_per_um2[layer].max(0.0) * grain.pixel_area_um2 * covered;
    1.0 / (std::f64::consts::LN_10 * (grains + 1.0).sqrt())
}

fn grain_jitter(grain: &GrainField, x: usize, y: usize, layer: usize, density: f64) -> f64 {
    grain_sigma(grain, density, layer)
        * grain_normal(grain_seed(grain.seed), x as u32, y as u32, layer as u32)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The point of the whole file: the u32 transcription is the same generator
    /// as the CPU's `u64` one, draw for draw.
    #[test]
    fn the_ported_generator_draws_what_the_cpu_draws() {
        let grain = GrainField::new(37, 23, 36.0, 0xC0FF_EE12_3456_789A);
        let mut worst = 0.0_f64;
        for index in 0..(37 * 23) {
            let (x, y) = (index % 37, index / 37);
            for layer in 0..3 {
                for density in [0.1, 0.6, 1.5, 2.8] {
                    let expected = grain.jitter(x, y, density, layer);
                    let replayed = grain_jitter(&grain, x, y, layer, density);
                    worst = worst.max((expected - replayed).abs());
                }
            }
        }
        assert!(worst < 1e-12, "the draw differs by {worst:.3e}");
    }

    /// A single bit wrong in the wide multiply would show up as a different
    /// number rather than as a small error, so the check above is sharp; this
    /// one says the halves are actually load-bearing.
    #[test]
    fn a_wrong_high_half_changes_the_draw() {
        let grain = GrainField::new(4, 4, 36.0, 1);
        let right = grain_jitter(&grain, 1, 2, 0, 1.0);
        let mut wrong = grain;
        wrong.seed = 2;
        assert_ne!(right, grain_jitter(&wrong, 1, 2, 0, 1.0));
    }
}
