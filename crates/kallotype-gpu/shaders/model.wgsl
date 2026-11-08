// The spectral model: camera triple → spectrum → film layers → log exposure,
// then density → dye absorption → paper → reflectance → observer.
//
// This is a transcription of `kallotype_core`'s spectral path. Everything it
// needs arrives as constants — the basis, the dye and layer spectra, the
// illuminants, the observer, the three inverted systems and the grey-balance
// tables — because the one thing it must not do is solve anything the CPU solved
// differently.
//
// The exposure, the print and the scan are independent, and each has a branch for
// its flag; every combination reproduces the CPU's own.

// ---------------------------------------------------------------------------
// Exposure: camera triple → spectrum → film layers → log exposure.
// ---------------------------------------------------------------------------

// `c = reconstruct · rgb`: the coefficients of the three basis terms.
fn basis_coefficients(rgb: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(
        tables.reconstruct[0u] * rgb.x + tables.reconstruct[1u] * rgb.y + tables.reconstruct[2u] * rgb.z,
        tables.reconstruct[3u] * rgb.x + tables.reconstruct[4u] * rgb.y + tables.reconstruct[5u] * rgb.z,
        tables.reconstruct[6u] * rgb.x + tables.reconstruct[7u] * rgb.y + tables.reconstruct[8u] * rgb.z,
    );
}

fn spectral_log_exposure(rgb: vec3<f32>) -> vec3<f32> {
    let coefficients = basis_coefficients(rgb);
    var response = vec3<f32>(0.0);
    for (var i = 0u; i < L; i = i + 1u) {
        // Reflectance cannot be negative; the clamp is part of the model.
        let value = max(
            0.0,
            coefficients.x * tables.basis[i]
                + coefficients.y * tables.basis[L + i]
                + coefficients.z * tables.basis[2u * L + i],
        );
        response.x = response.x + tables.film[i] * value;
        response.y = response.y + tables.film[L + i] * value;
        response.z = response.z + tables.film[2u * L + i] * value;
    }

    let step = params.grid.y;
    var log_e = vec3<f32>(0.0);
    for (var layer = 0u; layer < 3u; layer = layer + 1u) {
        // Divided by the film's response to the same grey the reconstruction
        // produces, so turning spectra on changes separation, not exposure.
        let anchor = max(params.exposure_reference[layer], 1e-12);
        let normalised = response[layer] * step * 0.18 / anchor;
        log_e[layer] = log10_cpu(max(normalised, 1e-10));
    }
    return log_e;
}

// ---------------------------------------------------------------------------
// Print: negative density → transmitted spectrum → paper layers → density.
// ---------------------------------------------------------------------------

// Status densities in, analytical densities out. The characteristic curves are
// measured through status filters and already contain all three dyes; the dye
// curves are per-dye shapes. Feeding one to the other double-counts the overlap,
// which is what the inverted system undoes.
fn print_analytical(status: vec3<f32>) -> vec3<f32> {
    let unmixed = vec3<f32>(
        tables.print_analytical[0u] * status.x + tables.print_analytical[1u] * status.y + tables.print_analytical[2u] * status.z,
        tables.print_analytical[3u] * status.x + tables.print_analytical[4u] * status.y + tables.print_analytical[5u] * status.z,
        tables.print_analytical[6u] * status.x + tables.print_analytical[7u] * status.y + tables.print_analytical[8u] * status.z,
    );
    // The CPU clamps only when the system solved; on the identity fallback it
    // returns the densities it was handed.
    if (params.flags.w > 0.5) {
        return max(unmixed, vec3<f32>(0.0));
    }
    return unmixed;
}

// Status densities in, and the unmixing happens *here* rather than at the call
// site, because that is where the CPU does it: `PrintContext::response` takes
// status densities and its caller passes the same three numbers it was handed.
// Unmixing before the call instead would feed the grey balance a mean taken in
// the wrong space, which shifts the whole print without any one pixel looking
// obviously wrong.
fn print_response(status: vec3<f32>) -> vec3<f32> {
    let density_cmy = print_analytical(status);

    // The mask is present in the unexposed film and consumed where the dyes
    // form. With masking off its strength is zero and the fraction is one,
    // which makes the mask a constant without a branch.
    let reference = max(params.masking.w, 1e-9);
    let removed = params.masking.x * clamp(density_cmy.x / reference, 0.0, 1.0)
        + params.masking.y * clamp(density_cmy.y / reference, 0.0, 1.0)
        + params.masking.z * clamp(density_cmy.z / reference, 0.0, 1.0);
    let surviving = clamp(1.0 - removed, 0.0, 1.0);

    var response = vec3<f32>(0.0);
    for (var i = 0u; i < L; i = i + 1u) {
        var d = tables.print_mask[i] * surviving;
        d = d + density_cmy.x * tables.print_dye[i]
            + density_cmy.y * tables.print_dye[L + i]
            + density_cmy.z * tables.print_dye[2u * L + i];

        // Yellow removes blue, magenta green, cyan red — in hundreds of a
        // colour-correction unit, which is what the enlarger's dials say.
        let filtration = params.filters.x * tables.print_filter_bands[i] / 100.0
            + params.filters.y * tables.print_filter_bands[L + i] / 100.0
            + params.filters.z * tables.print_filter_bands[2u * L + i] / 100.0;

        let transmitted = exp2(-(d + filtration) * LOG2_10) * tables.print_illuminant[i];
        response.x = response.x + tables.print_paper[i] * transmitted;
        response.y = response.y + tables.print_paper[L + i] * transmitted;
        response.z = response.z + tables.print_paper[2u * L + i] * transmitted;
    }
    return response * params.grid.y;
}

// Overlapping dye bands make a neutral negative transmit a coloured spectrum,
// and the paper's own overlapping layers do not cancel it. The correction is
// defined on the neutral axis only, so colour casts caused by unequal densities
// survive — that is the crosstalk the model exists to express.
fn print_balanced(status: vec3<f32>) -> vec3<f32> {
    let response = print_response(status);
    // The mean is over status densities, because the neutral response is
    // unmixed inside `print_response` too.
    let mean = (status.x + status.y + status.z) / 3.0;
    let neutral = print_response(vec3<f32>(mean));
    let balance = cbrt_(neutral.x * neutral.y * neutral.z);
    return vec3<f32>(
        response.x * (balance / max(neutral.x, 1e-12)),
        response.y * (balance / max(neutral.y, 1e-12)),
        response.z * (balance / max(neutral.z, 1e-12)),
    );
}

fn print_expose(status: vec3<f32>) -> vec3<f32> {
    let balanced = print_balanced(status);
    return vec3<f32>(
        log10_cpu(max(balanced.x / max(params.print_reference.x, 1e-12), 1e-10)),
        log10_cpu(max(balanced.y / max(params.print_reference.y, 1e-12), 1e-10)),
        log10_cpu(max(balanced.z / max(params.print_reference.z, 1e-12), 1e-10)),
    );
}

// ---------------------------------------------------------------------------
// Scan: print density → reflectance → illuminant → observer → linear sRGB.
// ---------------------------------------------------------------------------

fn scan_analytical(status: vec3<f32>) -> vec3<f32> {
    let unmixed = vec3<f32>(
        tables.scan_analytical[0u] * status.x + tables.scan_analytical[1u] * status.y + tables.scan_analytical[2u] * status.z,
        tables.scan_analytical[3u] * status.x + tables.scan_analytical[4u] * status.y + tables.scan_analytical[5u] * status.z,
        tables.scan_analytical[6u] * status.x + tables.scan_analytical[7u] * status.y + tables.scan_analytical[8u] * status.z,
    );
    if (params.flags2.x > 0.5) {
        return max(unmixed, vec3<f32>(0.0));
    }
    return unmixed;
}

fn scan_colour(printed: vec3<f32>) -> vec3<f32> {
    let density_cmy = scan_analytical(printed);

    var xyz = vec3<f32>(0.0);
    for (var i = 0u; i < L; i = i + 1u) {
        var d = params.neutral.z
            + density_cmy.x * tables.scan_dye[i]
            + density_cmy.y * tables.scan_dye[L + i]
            + density_cmy.z * tables.scan_dye[2u * L + i];
        // The paper cannot reflect more than it receives; the dyes only take
        // light away, so no clamp is needed here.
        let light = exp2(-d * LOG2_10) * tables.scan_illuminant[i];
        xyz.x = xyz.x + light * tables.scan_cmf[i];
        xyz.y = xyz.y + light * tables.scan_cmf[L + i];
        xyz.z = xyz.z + light * tables.scan_cmf[2u * L + i];
    }
    xyz = xyz * params.grid.y;

    let normalised = vec3<f32>(
        xyz.x / max(params.white_xyz.x, 1e-12),
        xyz.y / max(params.white_xyz.y, 1e-12),
        xyz.z / max(params.white_xyz.z, 1e-12),
    );

    let rgb = vec3<f32>(
        tables.scan_matrix[0u] * normalised.x + tables.scan_matrix[1u] * normalised.y + tables.scan_matrix[2u] * normalised.z,
        tables.scan_matrix[3u] * normalised.x + tables.scan_matrix[4u] * normalised.y + tables.scan_matrix[5u] * normalised.z,
        tables.scan_matrix[6u] * normalised.x + tables.scan_matrix[7u] * normalised.y + tables.scan_matrix[8u] * normalised.z,
    );
    let white_relative = vec3<f32>(
        rgb.x / max(params.white_rgb.x, 1e-12),
        rgb.y / max(params.white_rgb.y, 1e-12),
        rgb.z / max(params.white_rgb.z, 1e-12),
    );

    // Grey balance: the paper's dyes overlap, so a neutral density does not
    // scan neutral. The table is sampled along the neutral axis and
    // interpolated; colour casts off that axis are left alone on purpose.
    let mean = (printed.x + printed.y + printed.z) / 3.0;
    let steps = params.neutral.y;
    let position = clamp(mean / params.neutral.x * steps, 0.0, steps);
    let low = u32(floor(position));
    let high = min(low + 1u, u32(steps));
    let fraction = position - floor(position);
    let neutral = mix(
        vec3<f32>(
            tables.scan_neutral[low * 3u],
            tables.scan_neutral[low * 3u + 1u],
            tables.scan_neutral[low * 3u + 2u],
        ),
        vec3<f32>(
            tables.scan_neutral[high * 3u],
            tables.scan_neutral[high * 3u + 1u],
            tables.scan_neutral[high * 3u + 2u],
        ),
        fraction,
    );
    let balance = cbrt_(max(neutral.x, 1e-12) * max(neutral.y, 1e-12) * max(neutral.z, 1e-12));
    return vec3<f32>(
        white_relative.x * balance / max(neutral.x, 1e-12),
        white_relative.y * balance / max(neutral.y, 1e-12),
        white_relative.z * balance / max(neutral.z, 1e-12),
    );
}

// ---------------------------------------------------------------------------
// The interface every pass calls.
// ---------------------------------------------------------------------------

fn model_exposure(linear: vec3<f32>) -> vec3<f32> {
    if (params.flags.x > 0.5) {
        return spectral_log_exposure(linear);
    }
    // Scalar exposure: the channel is its own layer's log exposure.
    return vec3<f32>(
        log10_cpu(max(linear.x, 1e-10)),
        log10_cpu(max(linear.y, 1e-10)),
        log10_cpu(max(linear.z, 1e-10)),
    );
}

fn model_positive(status: vec3<f32>) -> vec3<f32> {
    // A reversal film is its own picture: there is no print, no paper and no
    // enlarger between the development and the eye, so the density *is* the
    // image and what leaves is the light it transmits.
    if (params.flags2.y > 0.5) {
        // White is the film's clearest point: the projector's lamp, not a
        // correction. See `Positive` in `pipeline.rs`.
        let white = vec3<f32>(params.curve[0].y, params.curve[1].y, params.curve[2].y);
        return clamp(
            exp2(-(status + params.film_base.xyz - white) * LOG2_10),
            vec3<f32>(0.0),
            vec3<f32>(1.0),
        );
    }

    // What the enlarger sees: the channel's own light loss, with the film's base
    // density riding in the exponent, or the light the negative's dyes transmit.
    // The spectral print puts the measured mask into its integral instead, so the
    // base is added here only on the non-spectral path.
    var log_transmittance = -(status + params.film_base.xyz);
    if (params.flags.y > 0.5) {
        log_transmittance = print_expose(status);
    }

    // The paper's curve, and the enlarger's shift per layer: the print balance
    // solved it so that a mid-grey negative lands on the target density.
    let paper = vec4<f32>(params.image.x, params.image.y, params.image.z, params.anchor.w);
    var printed = vec3<f32>(0.0);
    for (var layer = 0u; layer < 3u; layer = layer + 1u) {
        printed[layer] = curve_density(paper, params.transition.w, log_transmittance[layer] + params.anchor[layer]);
    }

    if (params.flags.z > 0.5) {
        return clamp(scan_colour(printed), vec3<f32>(0.0), vec3<f32>(1.0));
    }
    return clamp(exp2(-printed * LOG2_10), vec3<f32>(0.0), vec3<f32>(1.0));
}
