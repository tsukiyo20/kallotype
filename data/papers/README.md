# Measured papers

`data/papers/` holds one `.kalopaper` per measured paper stock:

| file | what it is |
|---|---|
| `portra_endura.kalopaper` | KODAK PROFESSIONAL PORTRA ENDURA — the normal-contrast reference |
| `supra_endura.kalopaper` | KODAK PROFESSIONAL SUPRA ENDURA — the higher-contrast sibling |
| `endura_premier_metallic.kalopaper` | KODAK PROFESSIONAL ENDURA Premier Metallic — its own sheet and spectra |
| `fuji_crystal_archive_pearl.kalopaper` | FUJICOLOR CRYSTAL ARCHIVE DIGITAL PEARL — the first Fuji paper, and the first on a relative exposure axis |
| `endura_premier.kalopaper` | KODAK PROFESSIONAL ENDURA Premier — the non-metallic sister of the metallic paper, and the contrastiest so far |
| `polymax_ii_rc.kalopaper` | KODAK PROFESSIONAL POLYMAX II RC — black-and-white, and the only paper whose spectra are flat by necessity rather than measured |

A paper is a different file from a film on purpose: one characteristic curve
instead of three, a target reflectance instead of a base density, no mask, no
grain and no blur. The format is specified in
[`../films/FORMAT.md`](../films/FORMAT.md#paper-files-kalopaper).

Both former placeholders are gone: `c41_paper` became the Fuji paper, and
`bw_paper` became POLYMAX II RC. There are no invented papers left in the tree.

A note on the black-and-white paper: the model's paper is trichrome by
construction — three dye curves and three layer sensitivities feeding three
density channels — and a silver paper is one neutral record. Its file therefore
carries flat grey absorption and flat layer rows, with the reasoning in the
stock's note. Graded printing (the eight PolyMax filter curves) is not modelled;
the file carries the White Light curve, the softest of the nine.

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
[`../films/LICENSE`](../films/LICENSE).
