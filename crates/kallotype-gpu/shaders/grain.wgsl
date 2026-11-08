// Grain: the same generator the CPU runs, in a language without 64-bit integers.
//
// `kallotype_core::grain` models grain as counting statistics and draws the
// fluctuation from SplitMix64, seeded from the pixel, the layer, the lane and the
// film's seed. This file is that generator — the same constants, the same order
// of operations — and it is the reason that module's draw keeps twenty-three
// bits: a shader has no f64, so a value built from the fifty-three bits a f64
// draw would use is a *different number* here, and the two backends would render
// two different films rather than one film twice.
//
// WGSL has no 64-bit integers either, so the state is carried as a high/low pair
// of `u32`. Nothing about the algorithm changes: `mul_hi` is a 32x32 product
// split into sixteen-bit limbs, which is the textbook way to do it without a
// multiply-extended instruction. `replay.rs` checks the transcription against the
// CPU's own draw, so a mistake here is a test failure and not a plausible image.
//
// This file is concatenated ahead of both shaders, which is why it refers to
// `params` before either of them declares it.

/// A 64-bit unsigned value as two 32-bit halves.
struct U64 {
    hi: u32,
    lo: u32,
};

fn u64_xor(left: U64, right: U64) -> U64 {
    return U64(left.hi ^ right.hi, left.lo ^ right.lo);
}

fn u64_add(left: U64, right: U64) -> U64 {
    let lo = left.lo + right.lo;
    let carry = select(0u, 1u, lo < left.lo);
    return U64(left.hi + right.hi + carry, lo);
}

/// Logical shift right by a constant in `1..=63`.
fn u64_shr(value: U64, count: u32) -> U64 {
    if (count >= 32u) {
        return U64(0u, value.hi >> (count - 32u));
    }
    return U64(value.hi >> count, (value.lo >> count) | (value.hi << (32u - count)));
}

/// The high 32 bits of a 32x32 product.
///
/// Sixteen-bit limbs, because WGSL has no multiply-extended: the low half of a
/// `u32 * u32` is the plain multiply, and the high half is three of them and two
/// carries.
fn mul_hi(left: u32, right: u32) -> u32 {
    let a0 = left & 0xFFFFu;
    let a1 = left >> 16u;
    let b0 = right & 0xFFFFu;
    let b1 = right >> 16u;

    var t = a0 * b0;
    let carry0 = t >> 16u;
    t = a1 * b0 + carry0;
    let middle = t & 0xFFFFu;
    let carry1 = t >> 16u;
    t = a0 * b1 + middle;
    return a1 * b1 + carry1 + (t >> 16u);
}

/// The low 64 bits of a 64x64 product, which is all SplitMix64 needs.
fn u64_mul(left: U64, right: U64) -> U64 {
    // The cross terms only reach the high half through their low 32 bits.
    let cross = left.lo * right.hi + left.hi * right.lo;
    return U64(mul_hi(left.lo, right.lo) + cross, left.lo * right.lo);
}

/// SplitMix64's output for one state, which is also its next state.
fn splitmix64(state: U64) -> U64 {
    var value = u64_add(state, U64(0x9E3779B9u, 0x7F4A7C15u));
    value = u64_mul(
        u64_xor(value, u64_shr(value, 30u)),
        U64(0xBF58476Du, 0x1CE4E5B9u),
    );
    value = u64_mul(
        u64_xor(value, u64_shr(value, 27u)),
        U64(0x94D049BBu, 0x133111EBu),
    );
    return u64_xor(value, u64_shr(value, 31u));
}

/// The seed, as the halves `params.grain` carries.
fn grain_seed() -> U64 {
    return U64(params.grain.y, params.grain.x);
}

/// A uniform in `(0, 1)` for one pixel, layer and lane.
///
/// Re-seeded from the coordinates rather than advanced along the image, so the
/// grain does not depend on how the image was split into workgroups.
fn grain_uniform(x: u32, y: u32, layer: u32, lane: u32) -> f32 {
    var state = u64_mul(grain_seed(), U64(0xD6E8FEB8u, 0x6659FD93u));
    state = u64_xor(state, u64_mul(U64(0u, x), U64(0x9E3779B9u, 0x7F4A7C15u)));
    state = u64_xor(state, u64_mul(U64(0u, y), U64(0xC2B2AE3Du, 0x27D4EB4Fu)));
    state = u64_xor(state, u64_mul(U64(0u, layer), U64(0x165667B1u, 0x9E3779F9u)));
    state = u64_xor(state, u64_mul(U64(0u, lane), U64(0x2545F491u, 0x4F6CDD1Du)));

    // The shift that keeps the draw exact in f32; see `GrainField::uniform`.
    let bits = u64_shr(splitmix64(state), 41u).lo;
    return (f32(bits) + 0.5) * (1.0 / 8388608.0);
}

/// A standard normal by Box–Muller, deterministic in the pixel and the layer.
///
/// `flags2.z` says the film has one record: a silver emulsion is one grain
/// field, and drawing it per layer would give a monochrome negative a colour
/// cast made of noise.
fn grain_normal(x: u32, y: u32, layer_in: u32) -> f32 {
    let layer = select(layer_in, 0u, params.flags2.z > 0.5);
    let u1 = grain_uniform(x, y, layer, 0u);
    let u2 = grain_uniform(x, y, layer, 1u);
    return sqrt(-2.0 * log(u1)) * cos(6.283185307179586 * u2);
}

/// Standard deviation of the log-exposure fluctuation at `density`.
///
/// `sigma_logE = 1 / (ln 10 * sqrt(N))`, with `N` the number of developed grains
/// under the aperture. The `+ 1` is the empty aperture: counting zero events has
/// an uncertainty of one event, not zero.
fn grain_sigma(density: f32, layer: u32) -> f32 {
    let covered = 1.0 - exp2(-max(density, 0.0) * 3.321928094887363);
    let grains = max(params.grain_density[layer + 1u], 0.0) * params.grain_density.x * covered;
    return 1.0 / (2.302585092994046 * sqrt(grains + 1.0));
}

/// One symmetric tap of the stencil: the centre, then the first and second
/// neighbours. `params.grain_stencil` carries them already normalised and
/// already scaled by the aperture correction.
fn grain_tap(stencil: vec4<f32>, offset: u32) -> f32 {
    if (offset == 0u) {
        return stencil.x;
    }
    if (offset == 1u) {
        return stencil.y;
    }
    return stencil.z;
}

/// A coordinate held inside the image, the way `GrainField::clamp` holds it.
fn grain_clamp(value: i32, limit: u32) -> u32 {
    return u32(clamp(value, 0, i32(limit) - 1));
}

/// The fluctuation in log exposure for one layer of one pixel.
///
/// The counting statistics give the variance through an aperture and nothing
/// about its shape, so the shape is a stencil: a grain covers area, and its
/// neighbours share its fluctuation. The taps are symmetric and already scaled
/// so a wide aperture sees the counting statistics — see
/// `GrainField::with_grain_sizes` — which leaves this function with only the
/// convolution to do. A radius of zero is the delta the grain has been all
/// along, and costs one tap.
fn grain_jitter(index: u32, layer: u32, mean_density: f32) -> f32 {
    let width = max(params.grain.z, 1u);
    let height = max(params.grain.w, 1u);
    let x = index % width;
    let y = index / width;
    // One record, one field, one size: a silver emulsion draws the central
    // layer everywhere.
    let record = select(layer, 0u, params.flags2.z > 0.5);
    let stencil = params.grain_stencil[record];
    let sigma = grain_sigma(mean_density, record);
    let reach = i32(stencil.w);
    if (reach == 0) {
        return sigma * stencil.x * grain_normal(x, y, layer);
    }

    var sum = 0.0;
    for (var dy = -reach; dy <= reach; dy = dy + 1) {
        let row = grain_clamp(i32(y) + dy, height);
        let down = grain_tap(stencil, u32(abs(dy)));
        for (var dx = -reach; dx <= reach; dx = dx + 1) {
            let column = grain_clamp(i32(x) + dx, width);
            sum = sum + down * grain_tap(stencil, u32(abs(dx))) * grain_normal(column, row, layer);
        }
    }
    return sigma * sum;
}
