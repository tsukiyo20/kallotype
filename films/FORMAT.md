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

TOML, because it is metadata a person reads. The keys that matter:

| key | meaning |
|---|---|
| `schema` | `"film/v1"` |
| `id`, `label`, `process` | `process` is `negative`, `reversal` or `monochrome` |
| `[provenance]` | the publication, its page, the date, a checksum of the data sheet, and a note |
| `[character]` | what the film is, without rendering: `d_min`, `d_max`, `gamma`, `base_density`, `grains_per_um2`, `sigma_um` |
| `[development]` | the reference time and temperature the curves were drawn at |
| `[measured]` | one line per field: measured, borrowed, none, or placeholder |
| `[curves]` | the characteristic curve of each layer, in the model's units |
| `[grid]` | `start_nm`, `step_nm`, `len` — 380, 5, 71 for version 1 |
| `[[tables]]` | directory: `name`, `rows`, `offset` (from the start of the tables), `bytes`, `dtype` |

### Table names and order

A reader that knows version 1 may ignore the directory, because the order is
part of the format:

| name | rows | what it is |
|---|---|---|
| `layers` | 3 | layer sensitivities, R/G/B order |
| `dyes` | 3 | dye absorption, cyan/magenta/yellow, peak-normalised |
| `mask` | 1 | spectral density of base, fog and the orange mask |
| `cl_sensitivity` | 1 | a cyan-sensitive inhibitor layer, when the film has one |

Tables that are absent are absent because the film has none — a reversal has no
orange mask — not because a writer forgot them. A reader must treat a missing
table as zero, not as an error.

### Curves

`d_min` and `d_max` are densities. For a negative they are the dye's floor and
shoulder above base (`d_min` is typically 0, and `base_density` carries the
mask). For a **reversal** they are the other way round: `d_min` is the density
of the unexposed slide (about 3.3) and `d_max` is the clear film, because a
slide starts dark and clears as it is exposed.

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
