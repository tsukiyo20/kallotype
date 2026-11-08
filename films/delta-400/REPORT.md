# ILFORD DELTA 400: the film the development times were fitted to

*Kallotype film-data series, report 13 of 13. Version 1, 2026-11-09.
Data: `delta-400.kalofilm` (5,568 bytes). Code: `films/tools/`.*

## Abstract

We digitise ILFORD DELTA 400, a black-and-white negative, from the seven pages of
`d400_a.pdf` and release it as a 5.6 kB data file. It is the fourth silver film
in the series, and the one the model owes most to: its page-5 contrast-against-
time chart is what `development.rs` was fitted to, so the film appears twice —
once as a curve, once as the law that moves the curve.

**What the sheet gives.** One characteristic curve (ID-11 stock, 8 minutes at
24 °C, 367 points, residual **0.0094**), its base density (0.2799), and four
contrast-time charts. That is all: there is no MTF, no granularity figure and no
spectral-sensitivity chart anywhere in the seven pages. Three of the model's
five fields are therefore declared absences rather than borrowed numbers — the
blur is absent, the grain is the compiled placeholder, and the layer response is
flat because "panchromatic" is a statement about the visible band and not a
measured curve.

**The anchor.** ILFORD prints a *relative* exposure axis, so the page supports
one anchor: the ISO 5800 speed point, where the curve reaches D_min + 0.10. The
points are shifted by **+0.1903** to put it at the model's reference exposure,
exactly as HP5 PLUS is. The check this leaves is mid grey: the negative sits
**0.88** of a density above its base at 18 per cent grey, between HP5 PLUS's
0.83 and TRI-X's 0.55 — this curve's toe is short, so it reaches its plateau
early.

## 1. Introduction

DELTA 400 was the first monochrome stock derived in this project, and the first
stock whose development time a photographer actually changes. It is also the
place where the model's central claim — that development time is a physical
quantity with a curve — is checked against the same sheet twice: once as the
page-6 characteristic curve at eight minutes, and once as the page-5
contrast-against-time charts that the kinetics were fitted to.

The three absences matter as much as the curve. A colour sheet that published no
MTF would be unusual; a silver sheet that publishes no MTF, no granularity and
no sensitivity is ordinary, and a model that refused such a film would refuse
most of the black-and-white catalogue. The honest answer is the one HP5 PLUS
already used: carry the absence as a value.

## 2. Materials

**The data sheet.** ILFORD DELTA 400 PROFESSIONAL, `d400_a.pdf`, November 2018,
seven pages, retrieved 2026-11-08, SHA-256 `92d4b976…acdb4`.

| page | what it carries | used |
|---|---|---|
| 2 | reciprocity failure tables | not used |
| 3–4 | development times to EI 3200, the push ladder | not used |
| 5 | contrast–time graphs, four developers, two temperatures | the kinetics |
| 6 | the characteristic curve, ID-11 stock 8 min at 24 °C | the curve |

**The curve panel.** One curve on a ruled frame, digitised from the page's
raster at 367 columns — about 0.012 decades apart — with a y quantisation of one
pixel ≈ 0.002 of a density.

## 3. Methods

### 3.1 The curve, and the fit

The model's curve is a trapezoid of two softplus corners; the fit chooses the
corners and their rates and solves the two linear parameters exactly. This film
carried a single transition of 4.0 until 2026-11-09; the two-rate rising fit
gives **0.0094** from 0.0111, with the asymptote bounded by the ink (2.307
against a drawn top of 2.300) rather than by the old rate's 2.313.

The fitted base is 0.2799, against an ink floor of 0.2809 — a silver negative's
curve begins at base plus fog, and the model wants the silver above the base
with the base carried separately.

### 3.2 The anchor: a relative axis, and only one anchor

ILFORD prints no absolute exposure scale and no reference exposure. What the
page does support is the ISO definition: the speed point is where the curve
reaches D_min + 0.10, and it must sit 1.26 decades below the model's mid grey.
The points are shifted by **+0.1903** to put it there, which is the same
convention HP5 PLUS uses and the weakest anchor in the series by the account of
that report — it makes the film consistent with its rating by applying the
rating's own definition, so it cannot be checked against anything the page
prints.

What can be checked is the other end: at 18 per cent grey the negative sits
**0.88** of a density above base. That is between HP5 PLUS's 0.83 and TRI-X's
0.55, and it is higher than a colour negative's 0.55–0.75 because this curve's
toe is short: it is already on its plateau slope at the speed point, where
TRI-X's is still bending.

### 3.3 What the sheet does not give

- **No MTF.** `sigma_um` is absent, and the stock is flagged as falling back to
  the compiled blur.
- **No granularity figure.** The grain is the compiled placeholder, averaged
  across the channels so the silver grain stays neutral rather than colouring
  the image. The file says `grain = "placeholder"`.
- **No spectral-sensitivity chart.** A flat response across 380–730 nm is what
  "panchromatic" means at this resolution of claim, and the file carries it as
  three identical flat tables with a note saying it is not a measurement.

### 3.4 The development time, which is why this film is in the series

Page 5 plots contrast against time for four developers at two temperatures.
`development.rs` models that as

    γ(t) = γ_inf + (γ_0 − γ_inf) · e^(−t/τ)

and the four constants are what the chart gives: γ_inf, γ_0, τ, and the reference
time. The 2026-11-08 measurement note records the fit and the residual, and the
TRI-X 400 ladder later tested the shape on a different film in a different
developer — it came out 2.5 per cent high at 8 and 10 minutes and 1.3 per cent
at 12.

This report does not re-open that fit. It is worth saying, though, that the film
whose page the kinetics were read from had never been released as a film: the
model could move a negative through development before it could say what that
negative was.

## 4. Results

### Table 1 — the characteristic curve

| layer | base | d_max | γ /decade | log_e0 | rates | rms |
|---|---|---|---|---|---|---|
| all three | 0.2799 | 2.0271 | 0.6942 | −0.5422 | 5 / 4 | 0.0094 |

`d_max` is above the base: the absolute asymptote is 0.280 + 2.027 = 2.307,
against a drawn top of 2.300. Residuals are against the 367 points in `curves/`;
the largest is 0.030.

### Table 2 — the other measurables

| quantity | value | source |
|---|---|---|
| MTF | none | the sheet publishes none |
| grain | placeholder | the sheet publishes none |
| layers | flat | no sensitivity chart; "panchromatic" is the claim |
| dyes | none | a silver image |
| mask | none | a silver image |

### Figures

- `figures/01-curves.png` — the fit and the 367 digitised points.
- `figures/02-residuals.png` — point minus fit: no drift, a one-pixel
  quantisation staircase, and the largest excursions at the two ends.
- `figures/03-spectra.png` — three flat lines, which is the file saying
  "panchromatic and unmeasured" rather than a measured curve.

## 5. What is measured and what is decided

Measured: the curve at the reference development, its base, and the
contrast-against-time relation the kinetics are fitted to.

Decided:

1. **The 0.02 window** on the asymptote, as every other negative in the series.
2. **Eight minutes at 24 °C** as the reference — the curve the sheet draws.
3. **The speed-point anchor**, because the page prints nothing else.
4. **The three absences**, carried as values rather than filled from another
   stock.

## 6. Uncertainty and limits

The curve is a raster: 367 columns, one-pixel y quantisation, a residual of
0.0094 — twice the vector-read colour films and comparable with T-MAX 400's.
The asymptote is bounded by the ink and is not measured.

The anchor is the weakest in the series for the reason §3.2 gives: it applies
the rating to anchor the film and then reads the rating back as agreement. The
mid-grey density is the one number in this file that could disagree with the
anchor, and it is reported above rather than used to adjust it.

## 7. Availability and reproduction

`delta-400.kalofilm` carries the header, the tables and a SHA-256;
`kalo render --film-file` loads it. The figures are regenerated from `curves/`
and the file with

```bash
python3 ../tools/kalofilm.py --check delta-400.kalofilm       # magic, digest, sizes
python3 ../tools/kalofilm.py --csv /tmp/film delta-400.kalofilm
```

The points in `curves/` are in the model's exposure frame — the sheet's relative
axis shifted by +0.1903 — and carry absolute density, base included;
`curves/README.md` states the shift so the fit can be recomputed from the
sheet's own axis.

No image of the data sheet is reproduced in this directory.

## References

1. HARMAN technology, *ILFORD DELTA 400 PROFESSIONAL*, `d400_a.pdf`, November
   2018, pages 5 and 6.
2. Kallotype, *The `.kalofilm` format, version 1*, `../FORMAT.md`.
3. Kallotype, `films/hp5-plus/REPORT.md` — the speed-point anchor this film
   shares, and the case for declaring absences rather than filling them.
