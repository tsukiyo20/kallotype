// The two passes that need the model, at either end of the chain.
//
// Everything between them — halation, development, the inhibitors — is model
// independent, which is why it lives in `chain.wgsl` and is compiled once. These
// two are the only places where a scalar render and a spectral one differ, and
// they differ only in what `model_exposure` and `model_positive` do.

// Camera triple in, log exposure out.
@compute @workgroup_size(64)
fn expose(@builtin(global_invocation_id) id: vec3<u32>) {
    // One workgroup row per image row: 65 535 workgroups per dispatch
    // dimension is the WebGPU limit, which a 4 MP image already exceeds
    // in one dimension.
    if (id.x >= params.grain.z) {
        return;
    }
    let index = id.y * params.grain.z + id.x;
    if (index >= arrayLength(&exposure)) {
        return;
    }
    exposure[index] = vec4<f32>(model_exposure(source[index].rgb), 0.0);
}

// Negative density in, linear-light RGB out.
@compute @workgroup_size(64)
fn positive(@builtin(global_invocation_id) id: vec3<u32>) {
    // One workgroup row per image row: 65 535 workgroups per dispatch
    // dimension is the WebGPU limit, which a 4 MP image already exceeds
    // in one dimension.
    if (id.x >= params.grain.z) {
        return;
    }
    let index = id.y * params.grain.z + id.x;
    if (index >= arrayLength(&output)) {
        return;
    }
    output[index] = vec4<f32>(model_positive(density[index].xyz), 1.0);
}
