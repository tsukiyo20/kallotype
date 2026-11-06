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

Phase 0. The repository currently implements the characteristic curve and its
dependence on development time and temperature. It does **not** yet model
spectra, couplers, grain or halation. The built-in stocks are placeholders with
realistic numbers, not measurements — see [ROADMAP.md](ROADMAP.md).

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
cargo run --release --bin kalo -- render assets/testchart.png -o out/dev_065.png
cargo run --release --bin kalo -- render assets/testchart.png -o out/dev_12.png --dev 12.0
```

Or install the binary:

```bash
cargo install --path crates/kallotype-cli
kalo stocks
kalo curve --dev 9.0 --temp 22 --sweep
kalo render photo.png -o photo_c41.png --film c41_standard --dev 9.0 --ev +0.3
```

> **macOS:** if `cargo build` fails with *"You have not agreed to the Xcode
> license agreements"*, run `sudo xcodebuild -license accept` once. The system
> linker refuses to run until the licence is accepted, and `git` fails the same
> way.

## Research

The work is recorded as it happened, not rewritten afterwards:

- **[Research log](docs/RESEARCH-LOG.md)** — each step's question, method, result
  and what changed because of it.
- **[Data catalogue](docs/DATA-CATALOG.md)** — every dataset, what consumes it,
  and which components are still placeholders.
- **[ADRs](docs/)** — the decisions themselves, with their evidence.

## Development

```bash
just check     # fmt + clippy + tests — the same three CI runs
just run render assets/testchart.png -o out/a.png --dev 9
just bench     # compare RGB → spectrum reconstructions
kalo bake -o out/model.klut --size 33 --dictionary data/vegetation-hawaii/reflectance.csv
kalo render photo.png -o out/photo.png --dev 9 --lut out/model.klut
just deny      # licences, advisories and sources
```

`just` is a convenience, not a requirement: every recipe is a plain `cargo`
command, listed in [justfile](justfile) and explained in
[CONTRIBUTING.md](CONTRIBUTING.md).

Layout:

```
crates/kallotype-core/   the model — no dependencies, no I/O, no unsafe
crates/kallotype-io/     decoding and encoding, the only file-format code
crates/kallotype-cli/    the kalo binary, plus a library so commands are testable
crates/kallotype-spectral/ spectra, sensors and the RGB → spectrum benchmark
data/                    measured datasets, each with its provenance
scripts/                 fixture generators
docs/                    architecture notes (numbered, like ADRs)
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

## What this is not

- Not a LUT pack, and not a "film look" filter that happens to be called a
  simulation.
- Not a reimplementation of anything. The physics is public; every line here is
  written against published literature and, from phase 1 on, against data
  sheets that are digitised in this repository.
- Not a product yet. There is no GUI, no colour management, and no spectral
  dimension.

## Crates

| Crate | Role |
|---|---|
| `kallotype-core` | The reference model: curves, development kinetics, built-in stocks, render. No I/O, no unsafe. |
| `kallotype-io` | Decoding and encoding images. The only place that touches a file format. |
| `kallotype-cli` | The `kalo` binary. |

`kallotype-gpu` (wgpu) arrives in phase 4 and must match `kallotype-core`
within a stated tolerance.

## Data and licensing

Code is **Apache-2.0**. See [LICENSE](LICENSE).

Data is treated separately and tracked in [NOTICE.md](NOTICE.md): every
spectral curve, density curve and target value must record where it came from.
Nothing copied from another project's data files is accepted. Manufacturer data
sheets describe physical facts and are the intended source; the digitisation
work is ours.

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
