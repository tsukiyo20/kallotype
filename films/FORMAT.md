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
