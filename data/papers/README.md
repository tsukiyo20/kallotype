# Measured papers

`data/papers/` holds one `.kalopaper` per measured paper stock:

| file | what it is |
|---|---|
| `portra_endura.kalopaper` | KODAK PROFESSIONAL PORTRA ENDURA — the normal-contrast reference |
| `supra_endura.kalopaper` | KODAK PROFESSIONAL SUPRA ENDURA — the higher-contrast sibling |
| `endura_premier_metallic.kalopaper` | KODAK PROFESSIONAL ENDURA Premier Metallic — its own sheet and spectra |
| `fuji_crystal_archive_pearl.kalopaper` | FUJICOLOR CRYSTAL ARCHIVE DIGITAL PEARL — the first Fuji paper, and the first on a relative exposure axis |
| `endura_premier.kalopaper` | KODAK PROFESSIONAL ENDURA Premier — the non-metallic sister of the metallic paper, and the contrastiest so far |

A paper is a different file from a film on purpose: one characteristic curve
instead of three, a target reflectance instead of a base density, no mask, no
grain and no blur. The format is specified in
[`films/FORMAT.md`](../films/FORMAT.md#paper-files-kalopaper).

One placeholder remains — `bw_paper`, a fibre-based black-and-white paper — and
it lives in `crates/kallotype-core/build.rs` with the placeholder films, because
it is an invented curve, not a digitisation. The other placeholder, `c41_paper`,
was replaced by the Fuji paper.

## Sheets that were read and did not become papers

Two more Fuji sheets were digitised far enough to know:

- **Crystal Archive Type II** (technical specs PDF) has the dye and sensitivity
  charts but **no characteristic curves** at all. A paper without its H&D curve
  is half a stock, so it is not here.
- **Crystal Archive Digital Paper Type DPII** (AF3-212E) has all three charts.
  Its curves and spectra agree with the Pearl sheet to within 0.005 of density
  and 0.005 of normalised dye — the two sheets describe the same emulsion on
  different surfaces, and the model has no surface. Adding it would have been a
  duplicate with a different name.

The licence is CC BY-SA 4.0, as for the films; the full text is in
[`films/LICENSE`](../films/LICENSE).
