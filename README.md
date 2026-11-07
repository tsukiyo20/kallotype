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

`kallotype-gpu` (wgpu) arrives in phase 4 and must match `kallotype-core`
within a stated tolerance.

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
