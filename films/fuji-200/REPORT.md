# FUJIFILM 200: the coarse chart

*Kallotype film-data series, report 20 of 21. Version 1, 2026-11-09.
Data: `fuji-200.kalofilm` (5,499 bytes). Code: `films/tools/`.*

## Abstract

FUJIFILM 200 is a consumer colour negative whose sheet publishes two charts and
no more: characteristic curves and spectral sensitivity. There is no MTF and no
granularity figure anywhere in AF3-0261E, and figure 16 prints a mid-scale
neutral subject rather than three dye curves — so three of the five modelled
fields are borrowed and the file says so field by field.

The curves are the coarsest digitisation in the series: **128 points** per layer
(0.03 decades apart), fitted at **0.0115 / 0.0054 / 0.0107** with the two-rate
rising model. What this film adds to the series is a reminder that a published
film file can be mostly declared absences and still be the honest representation
of the stock.

## 1. Materials

**The data sheet.** FUJIFILM 200 Color Negative Film, publication AF3-0261E,
page 5, retrieved 2026-11-08. Both charts are on page 5.

**The panel.** A raster chart on a camera-stops axis; the reader takes 128
samples, which is all the reproduction resolves.

## 2. Methods

### 2.1 The fit and the base

| layer | base | d_max | γ /decade | log_e0 | rates | rms |
|---|---|---|---|---|---|---|
| red | 0.1348 | 1.6127 | 0.5305 | −0.3562 | 4 / 20 | 0.0115 |
| green | 0.3639 | 1.9188 | 0.6150 | −0.3412 | 12 / 20 | 0.0054 |
| blue | 0.7541 | 1.8879 | 0.6648 | −0.3312 | 2 / 16 | 0.0107 |

`stock check` prints a note on this film: the fitted base (0.1348) sits above
the lowest density the sheet draws (0.1039), so the model's curve bottoms out at
the base and cannot reach that one drawn point. On a 128-sample chart the base
is the least certain number in the file, and the check says which number to look
at rather than hiding the disagreement.

### 2.2 The anchor

Camera stops, no reference exposure, so the printing aim: green at 0.70 above
base at mid grey, shift **+0.7482** (2.5 stops) from the compiled table's
corner-midpoint anchor.

### 2.3 What is borrowed

Dyes, mask and blur. Figure 16 prints a mid-scale neutral rather than three
dyes; the sheet has no MTF panel, so `emulsion.sigma_um` is absent and the
render falls back to the compiled fit; and no granularity figure is published,
so the grain is the compiled placeholder, averaged so a silver-neutral film
stays neutral.

## 3. Results

### Table 1 — the other measurables

| quantity | value | source |
|---|---|---|
| layer sensitivities | three curves | page 5 |
| dyes | borrowed | the VISION3 500T digitisation |
| mask | borrowed | the 500T's minimum density |
| blur | borrowed | no MTF panel |
| grain | placeholder | no granularity figure |

### Figures

- `figures/01-curves.png` — the fits and the 128 digitised points.
- `figures/02-residuals.png` — the pixel quantisation dominates.
- `figures/03-spectra.png` — the measured layers and the borrowed spectra.

## 4. What is measured and what is decided

Measured: the three curves and the layer sensitivities, and nothing else.

Decided:

1. **The 0.02 asymptote window.**
2. **The printing-aim anchor.**
3. **The borrowed dyes, mask and blur, and the placeholder grain** — each
   declared in `[measured]`.

## 5. Uncertainty and limits

At 0.03 decades per sample, the curve is the least resolved in the series; the
residuals (0.005 to 0.012) are at the chart's pixel size, not below it. The base
sits a hundredth of a density above one drawn point, which the check prints as a
note.

There is no MTF and no granularity figure, so two of the model's spatial fields
are not this film's. The borrowing is the same one GOLD 200 makes, and for the
same reason: a model that only published films whose sheets were complete would
publish four.

## 6. Availability and reproduction

`fuji-200.kalofilm` carries the header, the tables and a SHA-256;
`kalo render --film-file` loads it.

```bash
python3 ../tools/kalofilm.py --check fuji-200.kalofilm
```

No image of the data sheet is reproduced in this directory.

## References

1. FUJIFILM, *FUJIFILM 200 Color Negative Film*, publication AF3-0261E, page 5.
2. Kallotype, `films/fuji-400/REPORT.md` — its faster sibling.
