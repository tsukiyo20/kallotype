// The interface: one uniform and seven buffers, declared once.
//
// Every shader and every pass binds the same set, and a pass that does not use
// one still declares it. That is deliberate: one binding map and one uniform
// layout means a pass cannot read the kernel table where it expected the model,
// and the failure mode this crate exists to rule out is pixels that look
// plausible and are wrong.
//
// Lanes are `vec4` and scalars are four-wide on purpose: a `vec4` is sixteen
// bytes in every address space, so neither side has to reason about padding.

// Wavelength samples on the model grid.
const L: u32 = 71u;
const LOG2_10: f32 = 3.321928094887363;
const LN_10: f32 = 2.302585092994046;
// How sharply a curve's straight line turns into its toe and shoulder is a
// property of the material, so it rides with the curve; see
// `kallotype_core::curve`.

struct Params {
    // Per layer: (d_min, d_max, gamma, log_e0).
    curve: array<vec4<f32>, 3>,
    // How sharply each curve turns: the three layers, then the paper.
    transition: vec4<f32>,
    // (paper d_min, paper d_max, paper gamma, exposure shift).
    image: vec4<f32>,
    // The enlarger's exposure shift per layer, then the paper's log_e0.
    anchor: vec4<f32>,
    // The film's minimum density in status terms: base, fog and mask.
    film_base: vec4<f32>,
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
    // (neutral-axis density span, neutral-axis steps, paper base density, _).
    neutral: vec4<f32>,
    // (exposure is spectral, print is spectral, scan is spectral, print solved).
    flags: vec4<f32>,
    // (the scan unmixing solved, unused, unused, unused).
    flags2: vec4<f32>,
    // (seed low, seed high, image width, image height) — all exact integers.
    grain: vec4<u32>,
    // (pixel area in µm², developed grains per µm² per layer).
    grain_density: vec4<f32>,
    // What the finishing stage was asked to do: (grain, halation, couplers, _).
    effects: vec4<u32>,
    // (scatter strength per layer, kernel length in taps).
    halation_scatter: vec4<f32>,
    // (reflection strength per layer, kernel length in taps).
    halation_reflection: vec4<f32>,
    // (scatter kernel offset, reflection kernel offset, unused, unused).
    halation_offsets: vec4<f32>,
    // (inhibition row 0, half-saturation density).
    couplers: vec4<f32>,
    // (inhibition row 1, kernel length in taps).
    couplers2: vec4<f32>,
    // (inhibition row 2, kernel offset).
    couplers3: vec4<f32>,
    // Where each layer's emulsion blur kernel starts in the kernel table.
    blur_offsets: vec4<u32>,
    // How long each layer's blur kernel is; zero means the layer is not blurred.
    blur_lengths: vec4<u32>,
};

// The spectral model's constants, in the order `kallotype_core::model` writes
// them. A scalar render leaves them at zero.
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
// The image as handed in.
@group(0) @binding(1) var<storage, read> source: array<vec4<f32>>;
// The image as handed back.
@group(0) @binding(2) var<storage, read_write> output: array<vec4<f32>>;
// The spectral model's tables; zeros for a scalar render.
@group(0) @binding(3) var<storage, read> tables: Tables;
// The chain's working buffers: log exposure, density, and one scratch plane.
@group(0) @binding(4) var<storage, read_write> exposure: array<vec4<f32>>;
@group(0) @binding(5) var<storage, read_write> density: array<vec4<f32>>;
@group(0) @binding(6) var<storage, read_write> scratch: array<vec4<f32>>;
// The halation and inhibitor kernels, concatenated. Empty when neither runs.
@group(0) @binding(7) var<storage, read> kernels: array<f32>;
