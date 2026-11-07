# Kallotype

**Film simulation, with developing time as a dimension.**

Kallotype renders a digital image through a physical model of a photographic
negative, a development step, and a print — and treats *how long the film was
developed* as a first-class parameter, not as a separate preset.

> *Kallotype* — from the Greek **kalos** (beautiful) and **typos** (impression).
> The name William Henry Fox Talbot gave his negative-positive process in 1841,
> before English flattened it into "calotype".

---

## Status

Phases 0–3 are in place: the characteristic curve and its dependence on
development time and temperature, the spectral exposure path, the spectral print
and the spectral scan. Phase 5 is in: **grain** (`--grain`), modelled as a
particle process on the film's own scale, and **halation** (`--halation`), the
light that scatters in the emulsion and reflects off the base. Phase 6 has
started with **DIR couplers** (`--couplers`): development inhibition between
layers, with diffusion, and **masking couplers**: the orange mask is consumed as
the cyan dye forms, so the mask and the dye's unwanted absorption cancel.

The spectral path is reached with `--spectral` (and `--spectral-print`,
`--spectral-scan`); without those flags the renderer uses the per-channel scalar
model, which is exact for neutrals and cheap everywhere. The spectral path runs
on the film's and the paper's **measured** dye curves, compiled in — including
the orange mask, which is coupled rather than constant.

What works today:

```console
$ kalo curve --dev 3.0
  develop   3.00 min @ 20.0 °C  →  3.00 effective min
  contrast  ×0.705  (R 0.423  G 0.444  B 0.465)
  fog       -0.016 density
  speed     +0.046 log10 E  (+0.15 stops)

$ kalo curve --dev 12.0
  develop   12.00 min @ 20.0 °C  →  12.00 effective min
  contrast  ×1.177  (R 0.706  G 0.741  B 0.777)
  fog       +0.018 density
  speed     -0.037 log10 E  (-0.12 stops)
```

## Quick start

```bash
cargo build --release
cargo run --release --bin kalo -- render crates/kallotype-cli/assets/testchart.png -o out/dev_065.png
cargo run --release --bin kalo -- render crates/kallotype-cli/assets/testchart.png -o out/dev_12.png --dev 12.0
```

Or install the binary from crates.io:

```bash
cargo install kallotype-cli
kalo stocks
kalo curve --dev 9.0 --temp 22 --sweep
kalo render photo.png -o photo_c41.png --film c41_standard --dev 9.0 --ev +0.3
```

The library is on crates.io too — [`kallotype-core`](https://crates.io/crates/kallotype-core),
[`kallotype-spectral`](https://crates.io/crates/kallotype-spectral),
[`kallotype-io`](https://crates.io/crates/kallotype-io).

> **macOS:** if `cargo build` fails with *"You have not agreed to the Xcode
> license agreements"*, run `sudo xcodebuild -license accept` once. The system
> linker refuses to run until the licence is accepted, and `git` fails the same
> way.

## What is published, and what is not

This repository is the **code**. The datasets it was developed against and the
research notes that record the reasoning are kept locally and are not published
here: they are the product of a separate digitisation effort, and some of the
sources they describe are not redistributable in any case.

The consequence is deliberate: the model is self-contained — every measured
constant it needs is compiled in — but the tests that re-read the raw datasets
are `#[ignore]`d, and the benchmark needs a reflectance CSV passed to `--data`.

## Development

```bash
just check     # fmt + clippy + tests — the same three CI runs
just run render crates/kallotype-cli/assets/testchart.png -o out/a.png --dev 9
just bench     # compare RGB → spectrum reconstructions
kalo bake -o out/model.klut --size 33 --dictionary spectra.csv
kalo render photo.png -o out/photo.png --dev 9 --lut out/model.klut
just deny      # licences, advisories and sources
```

`just` is a convenience, not a requirement: every recipe is a plain `cargo`
command, listed in [justfile](justfile).

### Publishing

Four crates, and they go up in dependency order: `kallotype-spectral`, then
`kallotype-core`, then `kallotype-io` and `kallotype-cli`. Only the first can be
packaged before the rest exist on crates.io — a path dependency carries a
version, and packaging resolves that version against the registry, so
`kallotype-core` cannot be built for upload until `kallotype-spectral` is
already there.

Layout:

```
crates/kallotype-core/   the model — no dependencies, no I/O, no unsafe
crates/kallotype-io/     decoding and encoding, the only file-format code
crates/kallotype-cli/    the kalo binary, plus a library so commands are testable
crates/kallotype-spectral/ spectra, sensors and the RGB → spectrum benchmark
```

## The model

```
linear RGB ──► log10 E ──► negative density ──► print density ──► linear RGB
                             ▲   H&D curve         ▲   paper curve,
                             │   + development     │   balanced on 18 % grey
                             └─────────────────────┘
```

Three things are worth calling out:

1. **Development is kinetic, not a preset.** Contrast follows
   `γ(t) = γ∞ − (γ∞ − γ₀)·e^(−t/τ)` over an *effective* time that compensates
   temperature with a Q10 law. Long development also raises fog and shifts speed.
2. **The print balance is solved, not dialled in.** The enlarger exposure is
   computed in closed form so that an 18 % grey card lands on the paper's target
   reflectance. This is what an operator does with a test strip.
3. **Everything is f64 and in physical units**, so a GPU implementation can be
   checked against this one rather than trusted.
4. **Halation is light, so it is added to the exposure.** Two unit-sum Gaussian
   kernels — a short near-neutral scatter and a long red reflection, both in
   micrometres of film rather than pixels — move the exposure around, and a
   documented fraction returns. It runs before grain, because it is light
   exposing the emulsion and grain is what that light develops.
5. **Couplers are chemistry, not a colour matrix.** A layer that develops releases
   an inhibitor that suppresses its neighbours', and its own, further
   development — which is where interimage colour correction and the light line
   along a dark edge come from. It is a matrix with a spatial kernel, and the
   matrix can be fitted rather than typed: `fit_inhibition` recovers the matrix
   that produced a set of measured patch densities.
6. **The orange mask is not a colour, it is a coupler.** The cyan layer carries
   a coloured coupler that absorbs blue and is destroyed wherever cyan dye is
   made, so the mask's absorption and the dye's unwanted absorption cancel. That
   is why an unexposed negative is orange and an exposed one is not, and it is
   modelled as a term on the base density rather than as a constant.
7. **Grain is a count, not noise.** A pixel is an aperture over a random
   arrangement of developed grains, so its exposure has counting statistics:
   `σ_logE = 1/(ln 10 · √N)` where `N` is how many grains the pixel holds. That
   one expression gives Selwyn granularity (`σ ∝ 1/√area`, so grain survives a
   change of scan resolution), keeps a blank frame clean and a shoulder clean,
   and needs a single parameter — the developed grain density — instead of a
   curve of `σ` against density fitted by hand.

## What this is not

- Not a LUT pack, and not a "film look" filter that happens to be called a
  simulation.
- Not a reimplementation of anything. The physics is public; every line here is
  written against published literature and against manufacturer data sheets.
- Not a product yet. There is no GUI and no colour management.

## Crates

| Crate | Role |
|---|---|
| `kallotype-core` | The reference model: curves, development kinetics, built-in stocks, render. No I/O, no unsafe. |
| `kallotype-io` | Decoding and encoding images. The only place that touches a file format. |
| `kallotype-cli` | The `kalo` binary. |

### `kallotype-gpu`

A wgpu backend that must agree with `kallotype-core`. Both models are
transcribed into WGSL and nothing else: the prepared render hands over what the
CPU solved, or — where the model integrates over wavelength and there is no
answer to hand over — the tables it integrates on, and tests compare the two on
the same pixels.

Across a 2 048-pixel grid that spans the toe and the shoulder, the worst
per-channel difference in linear light is:

| render | worst difference |
|---|---|
| scalar | 3.0 × 10⁻⁷ |
| spectral exposure | 3.6 × 10⁻⁷ |
| spectral print | 8.2 × 10⁻⁷ |
| all three stages | 1.0 × 10⁻⁶ |
| halation | 3.1 × 10⁻⁷ |
| DIR couplers | 2.9 × 10⁻⁷ |
| everything the model has | 7.0 × 10⁻⁷ |

against a stated tolerance of 1 × 10⁻⁴.

The tolerance is the contract. A GPU port that "looks right" is how a film
simulation acquires two different films.

**Grain**, **halation** and the **DIR couplers** are all implemented, which makes
the backend the whole model rather than the front of it.

Grain is the sharpest constraint on the transcription. Its draw is SplitMix64 — 64-bit arithmetic, which WGSL has no
integers for — so `grain.wgsl` runs the same generator on pairs of `u32`, and
`grain.rs` keeps twenty-three bits of state rather than fifty-three so that the
draw is exact in an `f32`. For a random number "close enough" is false: the two
backends either draw the same number or they have made two films.

Halation and the couplers move light between pixels, so they need the frame in a
buffer: the backend runs one dispatch when there is nothing spatial and a chain of
up to seven when there is, skipping the passes that are off. A test renders the
same frame both ways and asserts the two are **bit-identical**, because two ways
to run a model is two ways to disagree.

What is refused — with an error naming it, not a shrug — is a **baked exposure
table** and a **dictionary prior**: a sampled cube and a per-pixel non-negative
least squares are their own models, and neither is expressible as a constant
matrix.

It is wired into the CLI behind a feature flag, because wgpu is about two hundred
crates and a command line tool does not need a GPU to be useful:

```bash
cargo install kallotype-cli --features gpu
kalo render photo.png -o out/photo.png --gpu
```

The report always says which backend ran and which device it was:

```text
  backend   gpu — Apple M4 (Metal)
```

`--gpu` falls back to the CPU with a warning — never silently, never with an
error — when there is no adapter or when the render needs a table or a dictionary.
The message names the stage, because the backend is asked rather than assumed. At eight bits per channel the two
backends agree to within one level; under a megapixel the files are usually
byte-identical, but that is a coincidence of where samples land on rounding
boundaries rather than a promise.

Measured on 2 073 600 pixels, CPU against GPU including upload, dispatch and
readback:

| render | cpu | gpu | ratio |
|---|---|---|---|
| scalar | 106 ms | 23 ms | 4.5 × |
| all three spectral stages | 3 062 ms | 36 ms | 84 × |
| the same, with grain | 3 174 ms | 33 ms | 97 × |
| the same, with halation and couplers | 3 356 ms | 45 ms | 74 × |

The spectral path is where the device earns its place: seventy-one wavelength
samples per pixel across four integrations is exactly the work a GPU is for. Below
about a megapixel of scalar work the fixed cost of a device and a readback is the
larger term, and the CPU wins — which is worth knowing before passing `--gpu` to
make a small image.

## Licence

Code is **Apache-2.0**. See [LICENSE](LICENSE).

The measured curves that ship compiled into the crate are our own digitisation
of published manufacturer data sheets; the data sheets themselves are not
redistributed. Nothing copied from another project's data files is accepted.

## Contributing

Early days — open an issue before a large pull request. Useful contributions
right now: curve digitisation, test images with known exposure, and critiques of
the development model.

## References

- Hurter & Driffield, *Photo-chemical Investigations* (1890) — the H&D curve.
- Mees & James, *The Theory of the Photographic Process*, 4th ed. — development
  kinetics.
- Hunt, *The Reproduction of Colour*, 6th ed. — couplers and interimage effects.
- Giorgianni & Madden, *Digital Color Management*, 2nd ed. — the negative/print
  pipeline.
- Mallett & Yuksel, *Spectral Primary Decomposition for Rendering with sRGB
  Reflectance* (2019) — spectral upsampling, for phase 2.
