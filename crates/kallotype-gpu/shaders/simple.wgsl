// The whole model in one dispatch, for a render with no spatial effect.
//
// Halation and the DIR couplers move light between pixels, so they need the frame
// in a buffer and a chain of passes. Without them there is nothing to keep, and
// this is one invocation per pixel from the file to the file.

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let index = id.x;
    if (index >= arrayLength(&source)) {
        return;
    }
    let density = develop(index, model_exposure(source[index].rgb));
    output[index] = vec4<f32>(model_positive(density), 1.0);
}
