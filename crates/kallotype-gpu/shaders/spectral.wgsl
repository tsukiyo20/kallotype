// The spectral model, one invocation per pixel.
//
// This is a transcription of `kallotype_core`'s exposure, print and scan into
// WGSL: the same seventy-one-point integration, the same tables, the same
// clamps. Everything it needs arrives as constants — the basis, the dye and
// layer spectra, the illuminants, the observer, the three inverted systems and
// the grey-balance tables — because the one thing this must not do is solve
// anything the CPU solved differently.
//
// The three stages are independent. A render can integrate the exposure and
// then print per channel, or the reverse; the flags in `params.flags` choose,
// and every combination has a branch that reproduces the CPU's own.
//
// ## Layout
//
// `Params` is deliberately written as plain `vec4`s and `Tables` as plain
// `array<f32, N>`s, so that neither side has to reason about padding: a `vec4`
// is sixteen bytes everywhere, and an `f32` array has stride four. The Rust
// struct is built by appending in exactly the order declared below.

const L: u32 = 71u;
const LOG2_10: f32 = 3.321928094887363;

struct Params {
    // Per layer: (d_min, span, slope_factor, log_e0).
    curve: array<vec4<f32>, 3>,
    // (paper d_min, paper span, enlarger slope, exposure shift).
    image: vec4<f32>,
    // The per-layer anchor log exposure.
    anchor: vec4<f32>,
    // (wavelength samples, wavelength step, unused, unused).
    grid: vec4<f32>,
    // The film's response to a reconstructed 18 % grey, per layer.
    exposure_reference: vec4<f32>,
    // The print's grey balance, per layer.
    print_reference: vec4<f32>,
    // (masking strength per layer, density at which it is fully destroyed).
    masking: vec4<f32>,
    // (filter pack in colour-correction units, unused).
    filters: vec4<f32>,
    // XYZ of paper white.
    white_xyz: vec4<f32>,
    // RGB of paper white.
    white_rgb: vec4<f32>,
    // (neutral-axis density span, neutral-axis steps, paper base density,
    // unused).
    neutral: vec4<f32>,
    // (exposure is spectral, print is spectral, scan is spectral, the print
    // unmixing solved).
    flags: vec4<f32>,
    // (the scan unmixing solved, unused, unused, unused).
    flags2: vec4<f32>,
};

struct Tables {
    reconstruct: array<f32, 9>,
    basis: array<f32, 3u * L>,
    film: array<f32, 3u * L>,
    print_analytical: array<f32, 9>,
    print_dye: array<f32, 3u * L>,
    print_paper: array<f32, 3u * L>,
    print_illuminant: array<f32, L>,
    print_mask: array<f32, L>,
    print_filter_bands: array<f32, 3u * L>,
    scan_analytical: array<f32, 9>,
    scan_dye: array<f32, 3u * L>,
    scan_cmf: array<f32, 3u * L>,
    scan_illuminant: array<f32, L>,
    scan_matrix: array<f32, 9>,
    scan_neutral: array<f32, 3u * 33u>,
};

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read> input: array<vec4<f32>>;
@group(0) @binding(2) var<storage, read_write> output: array<vec4<f32>>;
@group(0) @binding(3) var<storage, read> tables: Tables;

// The same branch the CPU takes: `1/(1+e^-z)` overflows for large negative z,
// and half a picture at the shoulder is large negative z.
fn sigmoid(z: f32) -> f32 {
    if (z >= 0.0) {
        return 1.0 / (1.0 + exp(-z));
    }
    let e = exp(z);
    return e / (1.0 + e);
}

// WGSL has no base-ten logarithm; the CPU calls `f64::log10`.
fn log10_cpu(x: f32) -> f32 {
    return log(x) / log(10.0);
}

// `pow` wants a non-negative base and the products fed to it are integrals of
// non-negative tables, so the clamp is belt and braces rather than maths.
fn cbrt_(x: f32) -> f32 {
    return pow(max(x, 0.0), 1.0 / 3.0);
}

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
// curves are per-dye shapes. Feeding one to the other double-counts the
// overlap, which is what the inverted system undoes.
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
        var density = tables.print_mask[i] * surviving;
        density = density
            + density_cmy.x * tables.print_dye[i]
            + density_cmy.y * tables.print_dye[L + i]
            + density_cmy.z * tables.print_dye[2u * L + i];

        // Yellow removes blue, magenta green, cyan red — in hundreds of a
        // colour-correction unit, which is what the enlarger's dials say.
        let filtration = params.filters.x * tables.print_filter_bands[i] / 100.0
            + params.filters.y * tables.print_filter_bands[L + i] / 100.0
            + params.filters.z * tables.print_filter_bands[2u * L + i] / 100.0;

        let transmitted = exp2(-(density + filtration) * LOG2_10) * tables.print_illuminant[i];
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
        var density = params.neutral.z
            + density_cmy.x * tables.scan_dye[i]
            + density_cmy.y * tables.scan_dye[L + i]
            + density_cmy.z * tables.scan_dye[2u * L + i];
        // The paper cannot reflect more than it receives; the dyes only take
        // light away, so no clamp is needed here.
        let light = exp2(-density * LOG2_10) * tables.scan_illuminant[i];
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
    let balance = cbrt_(
        max(neutral.x, 1e-12) * max(neutral.y, 1e-12) * max(neutral.z, 1e-12),
    );
    return vec3<f32>(
        white_relative.x * balance / max(neutral.x, 1e-12),
        white_relative.y * balance / max(neutral.y, 1e-12),
        white_relative.z * balance / max(neutral.z, 1e-12),
    );
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let index = id.x;
    if (index >= arrayLength(&input)) {
        return;
    }

    let linear = input[index].rgb;

    var log_e: vec3<f32>;
    if (params.flags.x > 0.5) {
        log_e = spectral_log_exposure(linear);
    } else {
        // Scalar exposure: the channel is its own layer's log exposure.
        log_e = vec3<f32>(
            log10_cpu(max(linear.x, 1e-10)),
            log10_cpu(max(linear.y, 1e-10)),
            log10_cpu(max(linear.z, 1e-10)),
        );
    }

    let shift = params.image.w;
    var density = vec3<f32>(0.0);
    for (var layer = 0u; layer < 3u; layer = layer + 1u) {
        let curve = params.curve[layer];
        density[layer] = curve.x + curve.y * sigmoid(curve.z * (log_e[layer] + shift - curve.w));
    }

    // What the enlarger sees: the channel's own light loss, or the light the
    // negative's dyes transmit.
    var log_transmittance = -density;
    if (params.flags.y > 0.5) {
        log_transmittance = print_expose(density);
    }

    var printed = vec3<f32>(0.0);
    for (var layer = 0u; layer < 3u; layer = layer + 1u) {
        let z = params.image.z * (log_transmittance[layer] - params.anchor[layer]);
        printed[layer] = params.image.x + params.image.y * sigmoid(z);
    }

    var result: vec3<f32>;
    if (params.flags.z > 0.5) {
        result = clamp(scan_colour(printed), vec3<f32>(0.0), vec3<f32>(1.0));
    } else {
        result = clamp(exp2(-printed * LOG2_10), vec3<f32>(0.0), vec3<f32>(1.0));
    }

    output[index] = vec4<f32>(result, 1.0);
}
