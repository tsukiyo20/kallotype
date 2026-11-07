// The pieces every pass needs, model and space independent.
//
// `develop` is here rather than in the two model files because the characteristic
// curve is the same one in both: a scalar render and a spectral one differ in how
// they *reach* the log exposure, not in what happens to it afterwards.

fn sigmoid(z: f32) -> f32 {
    // The same branch the CPU takes: `1/(1+e^-z)` overflows for large negative
    // z, and half a picture at the shoulder is large negative z.
    if (z >= 0.0) {
        return 1.0 / (1.0 + exp(-z));
    }
    let e = exp(z);
    return e / (1.0 + e);
}

// Numerically stable `ln(1 + e^u)`, the same form the CPU uses: the direct one
// overflows for large u, and large u is the shoulder of every well-exposed frame.
fn softplus(u: f32) -> f32 {
    return max(u, 0.0) + log(1.0 + exp(-abs(u)));
}

// The characteristic curve, from its numbers and its transition.
//
// The slope is `gamma` times the difference of two logistic steps, which is a
// plateau between the corners and zero outside: toe, straight line, shoulder.
// A single logistic would have a point of maximum contrast and no straight line,
// which is not what a measured negative looks like.
//
// `transition` is how fast the corners are turned, and it comes from the
// material: 4 for a negative, 10 for a paper, whose curve has no straight line
// for the corners to bound and is expressed by letting them overlap. See
// `kallotype_core::curve`.
fn curve_density(c: vec4<f32>, transition: f32, x: f32) -> f32 {
    // A negative rises with exposure and a reversal falls: the signed span says
    // which and gamma stays the magnitude of the slope. Mirrors `curve.rs`.
    let span = c.y - c.x;
    let gamma = max(c.z, 1e-9);
    let half = 0.5 * abs(span) / gamma;
    let direction = select(-1.0, 1.0, span >= 0.0);
    let toe = c.w - half;
    let shoulder = c.w + half;
    let slope = max(transition, 1e-3);
    return c.x
        + direction
            * (gamma / slope)
            * (softplus(slope * (x - toe)) - softplus(slope * (x - shoulder)));
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

// The negative's density, with the grain fluctuation if one was asked for.
//
// The mean density is what sizes the fluctuation, so the curve runs twice — which
// is what keeps grain out of a blank frame and out of the shoulder without either
// case being special-cased.
fn develop(index: u32, log_e: vec3<f32>) -> vec3<f32> {
    let shift = params.image.w;
    var density = vec3<f32>(0.0);
    for (var layer = 0u; layer < 3u; layer = layer + 1u) {
        let mean = curve_density(params.curve[layer], params.transition[layer], log_e[layer] + shift);
        if (params.effects.x == 0u) {
            density[layer] = mean;
        } else {
            let jittered = log_e[layer] + grain_jitter(index, layer, mean);
            density[layer] = curve_density(params.curve[layer], params.transition[layer], jittered + shift);
        }
    }
    return density;
}
