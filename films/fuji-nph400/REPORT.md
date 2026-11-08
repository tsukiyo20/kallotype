# FUJICOLOR NPH 400: the emulsion PRO 400H replaced

*Kallotype film-data series, report 18 of 21. Version 1, 2026-11-09.
Data: `fuji-nph400.kalofilm` (5,620 bytes). Code: `films/tools/`.*

## Abstract

FUJICOLOR NPH 400 PROFESSIONAL is the emulsion FUJICOLOR PRO 400H replaced, and
this series has referred to it since the second report: PRO 400H's grain was
measured on NPH 400 frames, because the sheet publishes no rms granularity. It
has been a compiled stock with a note and no report since the first week.

The curves and the four layer sensitivities are measured here; the dye shapes
and the mask are borrowed from the VISION3 500T digitisation, because AF3-865E's
figure 21 prints a mid-scale neutral subject rather than three dyes. Refitted
with the series' two-rate rising model, the curves close at **0.0076 / 0.0158 /
0.0088** over 664 points each — the green record's 0.0158 is the worst residual
of any film in the series, and §6 says why.

**The anchor** is the printing aim, because the sheet prints camera stops and no
reference exposure: green at 0.70 above base at mid grey, shift **+1.0813** —
three and a half stops, the largest re-anchoring in the series.

## 1. Materials

**The data sheet.** FUJICOLOR NPH 400 PROFESSIONAL, publication AF3-865E, page 6,
retrieved 2026-11-08, SHA-256 `…`. Curves on page 6, layer sensitivities in
figure 19 on the same page.

**The panel.** A raster chart on a camera-stops axis. The curves are read
against the stops, which is the axis the sheet draws consistently; its log
exposure labels sit on a slightly different scale.

## 2. Methods

### 2.1 The fit

Two-rate rising, the series' model: the corners are chosen by a grid, the two
linear parameters are solved exactly for each choice, and the asymptote may not
sit below the highest drawn density.

| layer | base | d_max | γ /decade | log_e0 | rates | rms |
|---|---|---|---|---|---|---|
| red | 0.2284 | 2.1718 | 0.7337 | −0.0007 | 4 / 20 | 0.0076 |
| green | 0.3755 | 2.4627 | 0.9189 | −0.1267 | 2.5 / 4 | 0.0158 |
| blue | 0.7601 | 2.4125 | 0.8206 | −0.0417 | 2.5 / 20 | 0.0088 |

The green record is the outlier: a high slope (0.92 per decade) fitted over a
long, soft toe. Its residual is twice the other two and is the digitisation as
much as the model — the panel's green curve is the one drawn over the densest
part of the raster.

### 2.2 The anchor

The sheet prints camera stops, so the film is anchored on the printing aim:
green at 0.70 of a density above base at 18 per cent grey, shift **+1.0813**.
The compiled table this replaces had been anchored on the fitted corner
midpoint, which put the curve more than a decade — three and a half stops — away
from the aim.

### 2.3 What is borrowed

- **Dyes and mask.** AF3-865E's figure 21 prints a mid-scale neutral and a
  minimum-density curve rather than three dyes. The dye shapes and the mask come
  from the VISION3 500T digitisation, and `[measured]` says so.
- **Grain.** 5.42 grains/µm² for all three layers, from the same NPH 400 scans
  the series measured PRO 400H's grain on.
- **Blur.** The stock declares no `sigma_um`; the render falls back to the
  compiled VISION3 fit.

## 3. Results

### Table 1 — the other measurables

| quantity | value | source |
|---|---|---|
| layer sensitivities | four, including the cyan-sensitive layer | figure 19 |
| dyes | borrowed | the VISION3 500T digitisation |
| mask | borrowed | the 500T's minimum density |
| grain | 5.42 grains/µm² | measured on NPH 400 scans |
| blur | compiled fallback | no `sigma_um` declared |

### Figures

- `figures/01-curves.png` — the fits and the digitised points.
- `figures/02-residuals.png` — the green curve's long toe is where the residual
  lives.
- `figures/03-spectra.png` — the measured layers, the borrowed dyes and mask.

## 4. What is measured and what is decided

Measured: the three curves, the four layer sensitivities, the grain.

Decided:

1. **The 0.02 asymptote window.**
2. **The printing-aim anchor.**
3. **The borrowed dyes, mask and blur**, each declared in `[measured]`.

## 5. Uncertainty and limits

The green residual (0.0158) is the largest in the series and is reported rather
than fitted away: the digitisation is a raster whose green curve is drawn
through the densest ink on the page, and the two-rate model cannot follow the
wobble that the reproduction adds there. A cleaner reading of that one curve
would lower the number; nothing else about the film would change.

The anchor's three-and-a-half-stop shift is a statement about the old compiled
table, not about this sheet: the sheet's curves never moved, only where the
model placed mid grey on them.

## 6. Availability and reproduction

`fuji-nph400.kalofilm` carries the header, the tables and a SHA-256;
`kalo render --film-file` loads it.

```bash
python3 ../tools/kalofilm.py --check fuji-nph400.kalofilm
```

No image of the data sheet is reproduced in this directory.

## References

1. FUJIFILM, *FUJICOLOR NPH 400 PROFESSIONAL*, publication AF3-865E, page 6.
2. Kallotype, `films/fuji-pro400h/REPORT.md` — the film that replaced it, and
   the scans its grain was measured on.
