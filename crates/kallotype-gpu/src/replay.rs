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

use kallotype_core::{PreparedRender, ScalarModel, SpectralModel};

const LOG2_10: f64 = std::f64::consts::LOG2_10;

/// Replay a whole image, choosing the shader the render would choose.
pub(crate) fn render(pixels: &[[f64; 3]], prepared: &PreparedRender) -> Vec<[f64; 3]> {
    if let Some(model) = prepared.scalar_model() {
        return pixels.iter().map(|pixel| scalar(&model, *pixel)).collect();
    }
    if let Some(model) = prepared.spectral_model() {
        return pixels
            .iter()
            .map(|pixel| spectral(&model, *pixel))
            .collect();
    }
    panic!("the render is neither scalar nor closed-form spectral");
}

fn sigmoid(z: f64) -> f64 {
    if z >= 0.0 {
        1.0 / (1.0 + (-z).exp())
    } else {
        let e = z.exp();
        e / (1.0 + e)
    }
}

/// `scalar.wgsl`, stage for stage.
fn scalar(model: &ScalarModel, linear: [f64; 3]) -> [f64; 3] {
    std::array::from_fn(|layer| {
        let log_e = linear[layer].max(1e-10).log10() + model.exposure_shift;
        let curve = model.curve[layer];
        let negative = curve[0] + curve[1] * sigmoid(curve[2] * (log_e - curve[3]));
        let z = model.print[0] * (-negative - model.print[layer + 1]);
        let printed = model.paper[0] + model.paper[1] * sigmoid(z);
        (-printed * LOG2_10).exp2().clamp(0.0, 1.0)
    })
}

/// `spectral.wgsl`, stage for stage.
fn spectral(model: &SpectralModel, linear: [f64; 3]) -> [f64; 3] {
    let log_e = match &model.exposure {
        Some(exposure) => spectral_log_exposure(exposure, model.step_nm, linear),
        None => std::array::from_fn(|layer| linear[layer].max(1e-10).log10()),
    };

    let density: [f64; 3] = std::array::from_fn(|layer| {
        let curve = model.scalar.curve[layer];
        let log_e = log_e[layer] + model.scalar.exposure_shift;
        curve[0] + curve[1] * sigmoid(curve[2] * (log_e - curve[3]))
    });

    let log_transmittance = match &model.enlarger {
        Some(enlarger) => print_expose(enlarger, model.step_nm, density),
        None => density.map(|value| -value),
    };

    let printed: [f64; 3] = std::array::from_fn(|layer| {
        let z = model.scalar.print[0] * (log_transmittance[layer] - model.scalar.print[layer + 1]);
        model.scalar.paper[0] + model.scalar.paper[1] * sigmoid(z)
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
