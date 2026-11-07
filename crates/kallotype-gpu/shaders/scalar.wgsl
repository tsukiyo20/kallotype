// The scalar model, one invocation per pixel.
//
// This is a transcription of `kallotype_core::PreparedRender::render_pixel` into
// WGSL, and nothing else: it takes the numbers the CPU solved and applies the
// same arithmetic in f32. If the two ever disagree it is a bug in one of them,
// not a difference in model — which is what the tolerance test exists to catch.
//
// The uniform buffer is deliberately anonymous (`vec4` lanes with the names in
// the Rust struct): a mismatch between the two layouts is the one failure that
// would produce plausible-looking wrong pixels, so the Rust side writes it from
// `ScalarModel` and the test compares against the CPU.

struct Params {
    // Per layer: (d_min, span, slope_factor, log_e0).
    curve: array<vec4<f32>, 3>,
    // (paper d_min, paper span, enlarger slope, exposure shift).
    paper: vec4<f32>,
    // The per-layer anchor log exposure.
    anchor: vec3<f32>,
    _pad: f32,
};

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read> input: array<vec4<f32>>;
@group(0) @binding(2) var<storage, read_write> output: array<vec4<f32>>;

// The same branch the CPU takes: `1/(1+e^-z)` overflows for large negative z,
// and half a picture at the shoulder is large negative z.
fn sigmoid(z: f32) -> f32 {
    if (z >= 0.0) {
        return 1.0 / (1.0 + exp(-z));
    }
    let e = exp(z);
    return e / (1.0 + e);
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let index = id.x;
    if (index >= arrayLength(&input)) {
        return;
    }

    let linear = input[index].rgb;
    let shift = params.paper.w;
    var density: vec3<f32>;
    var result: vec3<f32>;

    for (var layer = 0u; layer < 3u; layer += 1u) {
        // The CPU clamps the linear value before the logarithm; so does this.
        let log_e = log(max(linear[layer], 1e-10)) / log(10.0) + shift;

        let curve = params.curve[layer];
        let negative = curve.x + curve.y * sigmoid(curve.z * (log_e - curve.w));

        // Scalar print: the paper sees the negative's transmission, per channel.
        let z = params.paper.z * (-negative - params.anchor[layer]);
        let printed = params.paper.x + params.paper.y * sigmoid(z);

        // Scalar scan: the density is the channel's light loss.
        result[layer] = clamp(exp2(-printed * log2(10.0)), 0.0, 1.0);
    }

    output[index] = vec4<f32>(result, 1.0);
}
