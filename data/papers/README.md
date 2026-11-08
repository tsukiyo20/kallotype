# Measured papers

`data/papers/` holds one `.kalopaper` per measured paper stock:

| file | what it is |
|---|---|
| `portra_endura.kalopaper` | KODAK PROFESSIONAL PORTRA ENDURA — the default paper |
| `supra_endura.kalopaper` | KODAK PROFESSIONAL SUPRA ENDURA — the higher-contrast sibling |
| `endura_premier_metallic.kalopaper` | KODAK PROFESSIONAL ENDURA Premier Metallic — its own sheet and spectra |

A paper is a different file from a film on purpose: one characteristic curve
instead of three, a target reflectance instead of a base density, no mask, no
grain and no blur. The format is specified in
[`films/FORMAT.md`](../films/FORMAT.md#paper-files-kalopaper).

The other two papers the renderer knows — `c41_paper` and `bw_paper` — are
placeholders, not measurements, and live in `crates/kallotype-core/build.rs`
with the placeholder films.

The licence is CC BY-SA 4.0, as for the films; the full text is in
[`films/LICENSE`](../films/LICENSE).
