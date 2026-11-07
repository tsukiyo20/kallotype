# Stock files

A stock — a film or a paper — as data rather than as code. This is the format
`kalo stock check` reads; ADR 0012 in the private notes explains why the format
had to exist before a third stock did.

```console
$ kalo stock check stocks/example.toml
stocks/example.toml
  An example negative, with plausible numbers (film)
  note  provenance placeholder: no document is claimed, and the render says so
  ok    red        no digitised points named; the curve is taken on trust
  ...
  base  status density [0.19, 0.58, 0.83], grains [3.6, 3.6, 3.6] per µm²

  usable.
```

## Why a file

Every stock in the model is thirty to forty numbers and four charts off a data
sheet. While they were Rust structs, the *n*th stock was an edit to the model.
As files they are transcriptions, and the checker is what keeps a transcription
honest.

## The format

TOML, in a subset small enough to parse without a serialiser: `[section]` and
`[section.key]` headers, `key = value`, `#` comments, double-quoted strings with
no escapes, numbers, and lists that may span lines.

| section | key | what |
|---|---|---|
| `[stock]` | `id`, `label`, `kind`, `claim` | identity; `kind` is `film` or `paper`, `claim` is `measured` or `placeholder` |
| `[provenance]` | `source`, `publication`, `page`, `retrieved`, `checksum` | where the numbers came from |
| `[curve.red]`, `[curve.green]`, `[curve.blue]` | `d_min`, `d_max`, `gamma`, `log_e0`, `transition` | the characteristic curve |
| same | `points`, `rms`, `x_scale` | optional: the digitised points to re-derive the fit from |
| `[base]` | film: `density`, `grains_per_um2`; paper: `target_mid_reflectance` | what is not on the curve |
| `[spectra]` | `dyes`, `layers` | three CSV paths each, on the 380–730 nm grid |

`transition` defaults to the negative's 4.0 per decade; a paper wants about 7 to
10, because a paper's curve has no straight line for its corners to bound.

## What the checker enforces

1. **A stock that claims to be measured must name its document**, page,
   retrieval date and checksum. Without them it is a placeholder whatever it
   says, and a render that uses it says so too.
2. **The curve must be a curve**: `d_min < d_max`, positive `gamma`, a non-zero
   transition.
3. **The numbers must match the points.** If `points` is given, the curve is
   evaluated against them and the residual compared with the declared `rms` to
   within ten per cent — the fit's own uncertainty. A transposed decimal, a
   dropped minus or a layer swapped by accident fails here instead of rendering
   plausibly.
4. **The spectra must be on the grid the model integrates on**: 71 samples from
   380 nm in 5 nm steps, finite and non-negative.

## Adding a stock

1. Digitise the four charts off the data sheet — characteristic curves, dye
   density, spectral sensitivity, and MTF if it is there. The scripts are in the
   private folder; each takes a page and writes a CSV.
2. Write the file, citing the publication, the page and the checksum of the PDF.
3. Run `kalo stock check`. If the numbers and the points disagree, the checker
   will not say which is right — only that one of them is wrong.
