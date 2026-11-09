# KODAK ULTRA MAX 400: the consumer film that prints its own reference

*Kallotype film-data series, report 22 of 24. Version 1, 2026-11-10.
Data: `kodak-ultramax400.kalofilm` (6,045 bytes). Code: `films/tools/`.*

## Abstract

KODAK ULTRA MAX 400 (E-7023, revised 2/16) is the last consumer colour negative
to join the catalogue, and the second film here whose sheet prints a reference
exposure: `Log H Ref: −1.44`. That one number is the anchor — no corner-midpoint
guess, no printing aim — so the curves sit where Kodak says an 18 per cent grey
lands, shifted +0.6953 into the model's exposure frame.

The three curves fit at **0.0027 / 0.0046 / 0.0036**, the tightest of any Kodak
sheet in the series. The dye panel prints a mid-scale neutral and a minimum
density rather than three dyes, so the mask is this sheet's own (0.21 to 0.99)
and the dye shapes are borrowed from the VISION3 500T; there is no MTF panel,
and the grain is not claimed because the sheet's Print Grain Index says in
print that it is not rms granularity.

## 1. Materials

**The data sheet.** KODAK ULTRA MAX 400 Film — Technical Data, publication
E-7023, revised 2/16, four pages, retrieved 2026-11-10, SHA-256
`6c22ba6d…41bf3`.

**The panels.** Page 4: characteristic curves (log H −4.0 to +1.0, density 0 to
4.0, three vector paths labelled B, G, R), spectral sensitivity (250–750 nm,
log S 0 to 4) and the dye panel (400–700 nm, a mid-scale neutral and D-min).
Page 3 prints the exposure targets and the Print Grain Index.

## 2. Methods

### 2.1 The curves

The sheet's log H axis is already absolute, so the only transformation is the
printed reference: the model exposes mid grey at log10(0.18) = −0.7447, the
sheet says mid grey sits at −1.44, so every point moves +0.6953.

| layer | base | d_max | γ /decade | log_e0 | rates | rms |
|---|---|---|---|---|---|---|
| red | 0.2851 | 1.6712 | 0.5095 | −0.4251 | 5 / 8 | 0.0027 |
| green | 0.6955 | 1.7695 | 0.5330 | −0.4851 | 6 / 6 | 0.0046 |
| blue | 0.9822 | 2.0063 | 0.5971 | −0.3851 | 5 / 20 | 0.0036 |

`d_max` is above the base. The bases are the fit's asymptotes and sit within
0.02 of the ink's floor (0.28 / 0.70 / 0.97).

### 2.2 The spectra

**Layers.** Page 4's three forming layers, read as 10^logS on the sheet's own
scale so their relative speed survives: peaks 530, 517 and 549 at 470, 550 and
650 nm for the yellow-, magenta- and cyan-forming layers.

**Mask.** The dye panel's lower curve is D-min, the film's minimum density —
0.21 to 0.99 across 400–700 nm, held flat outside. This is the model's mask:
base, fog and the orange mask as one spectrum.

**Dyes.** Borrowed. The sheet prints one mid-scale neutral, not three dye
curves, and the file says so in `[measured]`.

### 2.3 What is not measured

**Blur.** No MTF panel; the render falls back to the compiled fit.

**Grain.** Not claimed at all. Page 3 gives a Print Grain Index of 46 and states
that the index cannot be compared to rms granularity; a placeholder that pretends
otherwise would be worse than an empty field.

## 3. Results

### Figures

- `figures/01-curves.png` — the fits and the digitised points.
- `figures/02-residuals.png` — point minus fit, inside ±0.01.
- `figures/03-spectra.png` — the three sensitivities and the measured mask.

## 4. What is measured and what is decided

Measured: the curves, the layer sensitivities, the minimum density.

Decided:

1. **The 0.02 asymptote window**, because the shoulders are drawn to the ink.
2. **The printed reference**, which needs no decision — it is the sheet's own.
3. **The borrowed dyes and blur**, and the absent grain, each declared.

## 5. Uncertainty and limits

The residuals are the smallest of any Kodak film in the series, which is what a
four-page consumer sheet with vector art should give. The base densities are the
fit's asymptotes and agree with the ink's floor to 0.02.

The two absences are the interesting part. A consumer sheet publishes enough to
measure three of the format's five quantities and states plainly that its grain
scale is not the model's; the file records that rather than filling the field.

## 6. Availability and reproduction

`kodak-ultramax400.kalofilm` carries the header, the tables and a SHA-256;
`kalo render --film-file` loads it.

```bash
python3 ../tools/kalofilm.py --check kodak-ultramax400.kalofilm
```

No image of the data sheet is reproduced in this directory.

## References

1. Eastman Kodak Company, *KODAK ULTRA MAX 400 Film — Technical Data*,
   publication E-7023, revised 2/16, page 4.
2. Kallotype, *The `.kalofilm` format, version 1*, `../FORMAT.md`.
3. Kallotype, `films/gold-200/REPORT.md` — the other consumer sheet that
   borrows its dyes.
