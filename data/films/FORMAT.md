# The `.kalofilm` format, version 1

One film, one file. Little-endian throughout.

```
offset 0       8    magic "KALOFILM"
offset 8       4    version, u32 — currently 1
offset 12      4    header length, u32
offset 16      n    header, UTF-8 TOML
offset 16+n    m    tables, f64, in directory order
offset 16+n+m  32   SHA-256 of every byte before it
```

## Header

TOML, in the same subset the stock files use: `[section]` headers, `key =
value`, numbers, double-quoted strings, single-line arrays. Root keys come
before the first section.

| key | meaning |
|---|---|
| `schema` | `"film/v1"` |
| `id`, `label`, `process` | `process` is `negative`, `reversal` or `monochrome` |
| `tables` | the table names, in file order: `["layers", "dyes", "mask"]` |
| `[provenance]` | `publication`, `page`, `retrieved`, `checksum` (of the data sheet), `note` |
| `[character]` | what the film is, without rendering: `d_min`, `d_max`, `gamma`, `base_density`, `grains_per_um2`, `sigma_um` |
| `[development]` | `reference_time_min`, `reference_temp_c` — the conditions the curves were drawn at |
| `[measured]` | one line per field: measured, borrowed, none, or a placeholder, with where |
| `[curve.red]`, `[curve.green]`, `[curve.blue]` | `d_min`, `d_max`, `gamma`, `log_e0`, `transition` |
| `[grid]` | `start_nm`, `step_nm`, `len` — 380, 5, 71 for version 1 |

### Tables

`tables` lists the tables that follow, in order. Each name fixes its row count,
so the list alone is enough to walk the blob:

| name | rows | what it is |
|---|---|---|
| `layers` | 3 | layer sensitivities, R/G/B order |
| `dyes` | 3 | dye absorption, cyan/magenta/yellow, peak-normalised |
| `mask` | 1 | spectral density of base, fog and the orange mask |
| `cl_sensitivity` | 1 | a cyan-sensitive inhibitor layer, when the film has one |

`layers` and `dyes` are required: a film without primaries cannot be printed.
`mask` may be absent — a reversal has no orange mask — and an absent table is
how the format says "none", not "forgotten". `cl_sensitivity` is optional.

## Paper files: `.kalopaper`

A paper is not a film with fewer channels, and it is not the same file. It has
**one** characteristic curve — it records what is on the negative, it does not
sample a scene — a target reflectance instead of a base density, and no mask,
grain or blur. The container is identical; the magic and the extension say which
kind it is, so a reader rejects the wrong one before parsing anything:

```
offset 0       8    magic "KALOPAPR"
offset 8       4    version, u32 — currently 1
offset 12      4    header length, u32
offset 16      n    header, UTF-8 TOML
offset 16+n    m    tables, f64, in directory order
offset 16+n+m  32   SHA-256 of every byte before it
```

| key | meaning |
|---|---|
| `schema` | `"paper/v1"` |
| `id`, `label` | |
| `tables` | `["dyes", "layers"]` |
| `[provenance]` | as a film's |
| `[curve]` | **one** curve: `d_min`, `d_max`, `gamma`, `log_e0`, `transition` |
| `[character]` | `target_mid_reflectance` — the linear reflectance a balanced print reaches for an 18 % grey card |
| `[measured]` | one line per field |
| `[grid]` | as a film's |

Tables are `dyes` (3 rows) and `layers` (3 rows), both required. There is no
`mask` table and no `cl_sensitivity`: a paper has neither an orange mask nor a
second emulsion.

Paper files live in `data/papers/`, one per paper; film files live in
`data/films/`, one directory per film. The crate's stock tables are generated
from both at build time (`crates/kallotype-core/build.rs`), and
`tools/kalofilm.py` reads either kind by its magic.

## The source file: a stock before it is packed

A `.kalofilm` is written by a packer from a TOML stock file and the CSVs it
names; the packer and the digitisation scripts are not published, the points
they produce are. The source file is how a stock is authored and checked — it
carries the provenance the binary header repeats, plus the digitised points the
fit is re-derived from — and `kalo stock check` reads it and nothing else.

| section | key | what |
|---|---|---|
| `[stock]` | `id`, `label`, `kind`, `process`, `claim`, `borrowed`, `note` | identity, and what the file admits to owing |
| `[provenance]` | `source`, `publication`, `page`, `retrieved`, `checksum` | where the numbers came from |
| `[curve.red]`, `[curve.green]`, `[curve.blue]` | `d_min`, `d_max`, `gamma`, `log_e0`, `toe_transition`, `shoulder_transition`, `points`, `rms` | one curve per layer, and the points it was fitted to |
| `[emulsion]` | `sigma_um` | one blur per layer, in micrometres |
| `[base]` | `density`, `grains_per_um2` | what is not on the curve: status density and grain, one per layer |
| `[spectra]` | `constant`, `layers`, `mask`, `mask_path` | three sensitivities, one mask, and the name the packed file gives them |
| `[measured]` | `curves`, `layers`, `mask`, `mtf`, `grain`, `dyes` | one sentence per field: measured, borrowed or absent |

The shape, with most of it elided:

```toml
[stock]
id = "kodak_gold200"
label = "KODAK GOLD 200"
kind = "film"
process = "negative"
claim = "measured"
borrowed = ["spectra.dyes"]

[provenance]
publication = "E-7022"
page = 4
retrieved = "2026-11-09"
checksum = "sha256:..."

[curve.green]
d_min = 0.0
d_max = 1.6848
gamma = 0.5933
log_e0 = -0.5823
toe_transition = 4.0
shoulder_transition = 3.0
points = "../data/sensitometry/kodak_gold200_37.csv"
rms = 0.0060

[base]
density = [0.2553, 0.6442, 0.9843]
grains_per_um2 = [0.0, 0.0, 0.0]
```

The checker enforces four things. A stock that claims to be measured must name
its document, page, retrieval date and checksum. The curve must be a curve:
`d_min < d_max`, positive `gamma`, a positive transition. The numbers must match
the points — the curve is evaluated against them and the residual compared with
the declared `rms` to within ten per cent, so a transposed decimal or a dropped
minus fails there instead of rendering plausibly. And the spectra must be on the
grid the model integrates on: 71 samples from 380 nm in 5 nm steps, finite and
non-negative.

For a film, `[base].density` is the status density of the unexposed processed
film — base, fog and mask — one per layer in the order red, green, blue. The
curve is dye *above* that base, so its `d_min` is zero and its `d_max` is
measured from the base too. A paper writes one `[curve]` instead of three, and
carries `target_mid_reflectance` in `[base]`.

## Reading it

1. Check the magic and the version; anything else is a different file.
2. Check the digest over `bytes[0..len-32]`.
3. Parse the header.
4. Copy each table's bytes into a fixed `[f64; len]` array.

There is no compression and no pointer chasing: the table blob is contiguous and
5 kB of f64 is smaller than the header that describes it.

## Versioning

A new version changes the magic byte's version field. A version 2 reader must
read version 1 files; a version 1 reader refuses a version 2 file rather than
guessing. New tables may be added in a version 2 without breaking the directory
— that is what the directory is for.
