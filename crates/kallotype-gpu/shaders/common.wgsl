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
        let curve = params.curve[layer];
        let mean = curve.x + curve.y * sigmoid(curve.z * (log_e[layer] + shift - curve.w));
        if (params.effects.x == 0u) {
            density[layer] = mean;
        } else {
            let jittered = log_e[layer] + grain_jitter(index, layer, mean);
            density[layer] = curve.x + curve.y * sigmoid(curve.z * (jittered + shift - curve.w));
        }
    }
    return density;
}
