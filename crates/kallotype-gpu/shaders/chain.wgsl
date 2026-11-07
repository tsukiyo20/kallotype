// The spatial effects, as a separable blur split over two passes.
//
// Halation and the DIR couplers are different physics with the same shape: a
// quantity produced at one pixel arrives, reduced, at its neighbours. Both are a
// Gaussian whose width is given in micrometres of film, so the kernels arrive
// precomputed and normalised — the shader neither builds nor normalises one, it
// only applies them.
//
// A separable blur is two dispatches: this file's horizontal pass writes the
// half-blurred plane, its vertical pass reads it back. That is the whole reason
// the chain exists.
//
// Edges repeat the border pixel rather than renormalising the kernel, which is
// what keeps a uniform field flat right up to the border — the same choice
// `kallotype_core::psf` makes, and it has to be the same one or the two backends
// disagree in a band a few pixels wide.

// How much inhibitor a layer releases at a density: saturating, because the
// coupler is consumed.
fn coupler_release(value: f32, half: f32) -> f32 {
    let density = max(value, 0.0);
    return density / (density + half);
}

// The light that reaches the base is what the scene threw at the film, not the
// density it produced: the halo source is the exposure averaged over the layers.
fn halo_source(pixel: vec3<f32>) -> f32 {
    return (exp2(pixel.x * LOG2_10) + exp2(pixel.y * LOG2_10) + exp2(pixel.z * LOG2_10)) / 3.0;
}

fn image_width() -> u32 {
    return params.grain.z;
}

fn image_height() -> u32 {
    return params.grain.w;
}

fn tap_index(value: i32, limit: u32) -> u32 {
    return u32(clamp(value, 0, i32(limit) - 1));
}

// ---------------------------------------------------------------------------
// Halation, before development: it is light exposing the emulsion.
// ---------------------------------------------------------------------------

@compute @workgroup_size(64)
fn halation_horizontal(@builtin(global_invocation_id) id: vec3<u32>) {
    let index = id.x;
    if (index >= arrayLength(&scratch)) {
        return;
    }
    let width = image_width();
    let x = i32(index % width);
    let row = index - u32(x);

    var scatter = 0.0;
    let scatter_length = u32(params.halation_scatter.w);
    if (scatter_length > 0u) {
        let radius = i32(scatter_length / 2u);
        let offset = u32(params.halation_offsets.x);
        for (var tap = 0u; tap < scatter_length; tap = tap + 1u) {
            let source_x = tap_index(x + i32(tap) - radius, width);
            scatter = scatter + kernels[offset + tap] * halo_source(exposure[row + source_x].xyz);
        }
    }

    var reflection = 0.0;
    let reflection_length = u32(params.halation_reflection.w);
    if (reflection_length > 0u) {
        let radius = i32(reflection_length / 2u);
        let offset = u32(params.halation_offsets.y);
        for (var tap = 0u; tap < reflection_length; tap = tap + 1u) {
            let source_x = tap_index(x + i32(tap) - radius, width);
            reflection = reflection + kernels[offset + tap] * halo_source(exposure[row + source_x].xyz);
        }
    }

    scratch[index] = vec4<f32>(scatter, reflection, 0.0, 0.0);
}

@compute @workgroup_size(64)
fn halation_vertical(@builtin(global_invocation_id) id: vec3<u32>) {
    let index = id.x;
    if (index >= arrayLength(&exposure)) {
        return;
    }
    let width = image_width();
    let height = image_height();
    let x = index % width;
    let y = i32(index / width);

    var scatter = 0.0;
    let scatter_length = u32(params.halation_scatter.w);
    if (scatter_length > 0u) {
        let radius = i32(scatter_length / 2u);
        let offset = u32(params.halation_offsets.x);
        for (var tap = 0u; tap < scatter_length; tap = tap + 1u) {
            let source_y = tap_index(y + i32(tap) - radius, height);
            scatter = scatter + kernels[offset + tap] * scratch[source_y * width + x].x;
        }
    }

    var reflection = 0.0;
    let reflection_length = u32(params.halation_reflection.w);
    if (reflection_length > 0u) {
        let radius = i32(reflection_length / 2u);
        let offset = u32(params.halation_offsets.y);
        for (var tap = 0u; tap < reflection_length; tap = tap + 1u) {
            let source_y = tap_index(y + i32(tap) - radius, height);
            reflection = reflection + kernels[offset + tap] * scratch[source_y * width + x].y;
        }
    }

    // The halo is light, so it adds to the exposure and then goes back through
    // the logarithm: a black area next to a highlight really does get exposed.
    let log_e = exposure[index].xyz;
    var updated = vec3<f32>(0.0);
    for (var layer = 0u; layer < 3u; layer = layer + 1u) {
        let current = max(exp2(log_e[layer] * LOG2_10), 1e-10);
        let added = params.halation_scatter[layer] * scatter
            + params.halation_reflection[layer] * reflection;
        updated[layer] = log10_cpu(current + added);
    }
    exposure[index] = vec4<f32>(updated, 0.0);
}

// ---------------------------------------------------------------------------
// Development, between the two effects.
// ---------------------------------------------------------------------------

@compute @workgroup_size(64)
fn develop_pass(@builtin(global_invocation_id) id: vec3<u32>) {
    let index = id.x;
    if (index >= arrayLength(&density)) {
        return;
    }
    density[index] = vec4<f32>(develop(index, exposure[index].xyz), 0.0);
}

// ---------------------------------------------------------------------------
// DIR couplers, after development: the inhibitor acts on what has already formed.
// ---------------------------------------------------------------------------

@compute @workgroup_size(64)
fn couplers_horizontal(@builtin(global_invocation_id) id: vec3<u32>) {
    let index = id.x;
    if (index >= arrayLength(&scratch)) {
        return;
    }
    let length = u32(params.couplers2.w);
    if (length == 0u) {
        scratch[index] = vec4<f32>(0.0);
        return;
    }

    let width = image_width();
    let x = i32(index % width);
    let row = index - u32(x);
    let half = max(params.couplers.w, 1e-9);
    let radius = i32(length / 2u);
    let offset = u32(params.couplers3.w);

    var blurred = vec3<f32>(0.0);
    for (var tap = 0u; tap < length; tap = tap + 1u) {
        let source_x = tap_index(x + i32(tap) - radius, width);
        let neighbour = density[row + source_x].xyz;
        let released = vec3<f32>(
            coupler_release(neighbour.x, half),
            coupler_release(neighbour.y, half),
            coupler_release(neighbour.z, half),
        );
        blurred = blurred + kernels[offset + tap] * released;
    }
    scratch[index] = vec4<f32>(blurred, 0.0);
}

@compute @workgroup_size(64)
fn couplers_vertical(@builtin(global_invocation_id) id: vec3<u32>) {
    let index = id.x;
    if (index >= arrayLength(&density)) {
        return;
    }
    let length = u32(params.couplers2.w);
    if (length == 0u) {
        return;
    }

    let width = image_width();
    let height = image_height();
    let x = index % width;
    let y = i32(index / width);
    let radius = i32(length / 2u);
    let offset = u32(params.couplers3.w);

    var diffused = vec3<f32>(0.0);
    for (var tap = 0u; tap < length; tap = tap + 1u) {
        let source_y = tap_index(y + i32(tap) - radius, height);
        diffused = diffused + kernels[offset + tap] * scratch[source_y * width + x].xyz;
    }

    // `M[i][j]`: how much layer `j` suppresses layer `i`. The diagonal is the
    // highlight compression, the off-diagonal the interimage correction, and the
    // diffusion is what turns a local suppression into an edge effect.
    let suppressions = vec3<f32>(
        params.couplers.x * diffused.x + params.couplers.y * diffused.y
            + params.couplers.z * diffused.z,
        params.couplers2.x * diffused.x + params.couplers2.y * diffused.y
            + params.couplers2.z * diffused.z,
        params.couplers3.x * diffused.x + params.couplers3.y * diffused.y
            + params.couplers3.z * diffused.z,
    );

    let current = density[index].xyz;
    var inhibited = vec3<f32>(0.0);
    for (var layer = 0u; layer < 3u; layer = layer + 1u) {
        inhibited[layer] = max(current[layer] * max(1.0 - suppressions[layer], 0.0), 0.0);
    }
    density[index] = vec4<f32>(inhibited, 0.0);
}
