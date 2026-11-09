# Measured papers

`data/papers/` holds one `.kalopaper` per measured paper stock:

| file | what it is |
|---|---|
| `portra_endura.kalopaper` | KODAK PROFESSIONAL PORTRA ENDURA — the normal-contrast reference |
| `supra_endura.kalopaper` | KODAK PROFESSIONAL SUPRA ENDURA — the higher-contrast sibling |
| `endura_premier_metallic.kalopaper` | KODAK PROFESSIONAL ENDURA Premier Metallic — its own sheet and spectra |
| `fuji_crystal_archive_pearl.kalopaper` | FUJICOLOR CRYSTAL ARCHIVE DIGITAL PEARL — the first Fuji paper, and the first on a relative exposure axis |

A paper is a different file from a film on purpose: one characteristic curve
instead of three, a target reflectance instead of a base density, no mask, no
grain and no blur. The format is specified in
[`films/FORMAT.md`](../films/FORMAT.md#paper-files-kalopaper).

One placeholder remains — `bw_paper`, a fibre-based black-and-white paper — and
it lives in `crates/kallotype-core/build.rs` with the placeholder films, because
it is an invented curve, not a digitisation. The other placeholder, `c41_paper`,
was replaced by the Fuji paper.

The licence is CC BY-SA 4.0, as for the films; the full text is in
[`films/LICENSE`](../films/LICENSE).
