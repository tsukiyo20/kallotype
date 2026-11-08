# KODAK TRI-X 400: one record, and two curves that are not its own

*Kallotype film-data series, report 7 of 13. Version 1, 2026-11-08.
Data: `trix-400.kalofilm` (5,527 bytes). Code: `films/tools/`.*

## Abstract

We digitise KODAK TRI-X 400 (400TX), a black-and-white negative, from the 2002
Japanese edition of its technical data and release it as a 5.5 kB data file. It
is the first silver film in this series, and the first file whose film has one
record instead of three: no dyes, no orange mask, and a base density that is part
of the curve the sheet draws rather than a constant to subtract.

Three things make this sheet worth its own report.

**It is the old edition, and the sheet says so.** Its MTF curve and its spectral
sensitivity are not 400TX measurements: a note on the page states that both come
from the previous emulsion, Tri-X pan 5063, and that Kodak's data indicates the
information still applies. They are used — they are the only ones the sheet
gives — and both the file and this report say whose data they are.

**The graph's legend is crossed.** The sensitivity panel draws two curves, at
D = 0.3 and D = 1.0 above gross fog. The solid one is the *more* sensitive of the
two, and the lower criterion must be: reaching a density of 0.3 takes less
exposure than reaching 1.0, so its reciprocal is larger. The legend's swatches
assign the solid style to D = 1.0, which cannot be true; the curves are therefore
identified by the direction the criterion implies, not by the dash pattern.

**The grain is the coarsest in the tree.** A diffuse rms granularity of 17 at a
net density of 1.0, inverted through counting statistics at the curve's local
slope there (0.530 per decade), gives **0.1124 grains/µm²** — five times coarser
than PRO 400H's cyan layer and the first grain number in the series that makes the
renderer produce visible grain at a normal viewing size.

The curve is the 6-minute one of the D-76 family, the residual is 0.0049, the MTF
is σ 4.06 µm, and the speed point is half a stop late — §3.2 explains why that is
the drawing's and not the anchor's.

## 1. Introduction

Six colour films precede this one, and every one of them has three records, three
dyes and — if it is a negative — an orange mask. A silver film has none of that.
It is one emulsion, one sensitivity, one curve, and the silver that forms the
image absorbs uniformly across the visible, so its "dye" is a neutral density and
its "mask" does not exist.

The model has had a `Monochrome` process since the first black-and-white stock was
compiled, and two such stocks — ILFORD DELTA 400 and KODAK T-MAX 400 — but no
file. The difference matters: a compiled stock is a Rust literal that only this
code reads, while a file has to say what its tables mean, and the format's table
list has no way to say "no dyes" except by carrying three rows of zeros. That is
what this film's file carries, and §3.5 is about the two scripts that had to agree
on it.

## 2. Materials

**The data sheet.** KODAK PROFESSIONAL TRI-X 400 / TRI-X 320, Japanese edition,
2002, 16 pages, retrieved 2026-11-08, SHA-256 `910ff531…80256`. The English and
Japanese editions are both © 2002; the PDF was created on 10 October 2002. It is
a vector sheet throughout: the charts are paths and the axis numbers are text, so
no pixel is involved in any number below.

It is also, in 2026, a document that has to be recovered rather than fetched: the
publisher's URL answers 404, and the copy read here is a Wayback Machine snapshot
of March 2004, whose digest matches the October 2003 snapshot exactly. The sheet
is filed with a checksum and its state is a row in the shelf document rather than
a memory of having tested an instrument on it.

| printed page | what it holds |
|---|---|
| 10 | image structure: diffuse rms granularity 17, one MTF curve, spectral sensitivity at D = 0.3 and D = 1.0 |
| 11 | characteristic curves: 35 mm in a Versamat at 26.5 °C (6/7/9/11 min), 120 in T-MAX developer |
| 12 | characteristic curves: 35 mm and 120 in D-76, large tank, 20 °C, 1-minute agitation (6/8/10/12 min), and contrast-index curves for nine developers |

**What is digitised.** The 35 mm D-76 family on printed page 12 (four polylines
of 103 to 116 segments), the MTF and the sensitivity on printed page 10, and the
grain number. Calibration is from the page's own tick labels: 0.01 log units in
x and 0.008 of a density in y on the curve panel, 0.27 nm and 0.005 on the
sensitivity panel, and 0.004 and 0.006 of a decade on the MTF's two log axes.

## 3. Methods

### 3.1 Which curve

The sheet draws the film at four development times. The stock needs one, and the
choice is the sheet's own: its development table gives **6¾ minutes** for D-76 in
a large tank at 20 °C, and the drawn family starts at 6. The 6-minute curve is
therefore the nearest drawn development to the recommended one, and it is the
lowest-contrast of the four — γ 0.546 per decade.

The other three are digitised and kept. They are the development ladder — the
same film at 6, 8, 10 and 12 minutes — and on the day this report was written they
became the first manufacturer data the model's kinetics were checked against: the
four rungs moved the fog, ceiling, speed and toe constants out of the prior
column and into measurements. The model references the 6 minutes and 20 °C of the curve the
file carries, so `kalo render --dev 6 --temp 20` is this sheet's ink and any other
setting is a deliberate move away from it.

### 3.2 The anchor, and the half stop

This sheet prints no `Log H Ref`. Its log H axis is absolute lux-seconds, and the
anchor has to come from the standard that makes the axis mean anything: an ISO
400 film's speed point is at log H = log10(0.8/400) = −2.699, and the reference
exposure of an 18 per cent grey card sits 1.26 decades above it, at −1.4398. That
is exactly the number the five Kodak colour sheets print as `Log H Ref`, so the
same relation is used here and the axis is shifted by the same **+0.6953** the
PORTRA 400 sheet needed.

**The check.** At the nominal speed point the 6-minute curve stands 0.068 of a
density above the fitted base where ISO 6 asks for 0.10. Following the drawn curve
to where it does reach 0.10 puts the crossing at log H = −2.54: **0.52 of a stop**
later than the rating. The sheet's recommended 6¾ minutes would land between the
6- and 8-minute curves and close about a third of that.

This is the largest speed discrepancy in the series — PORTRA 400's sheet is 0.60
of a stop late and PORTRA 800's 0.44 — and in all three cases the direction is the
same: the drawn curves are slower than their ratings. It is reported, not
corrected, because the rating is the film's and the model consumes the curve.

### 3.3 The fit

A silver negative's curve starts at base plus fog and climbs, so the fit uses
`--two-rates --rising --asymptote-window 0.02`. The asymptote comes out at 1.748,
which is 0.012 above the highest density the sheet draws — the model's maximum is
the ink's. The base is the fit's asymptote under the toe, 0.2618, and the curve is
that curve shifted down to zero, which is the model's convention for a negative.
The residual is **0.0049**.

The corners are asymmetric in a way the colour negatives' are not: a soft toe
(rate 3) against a shoulder at 8. That is what a conventional-grain emulsion
draws, and the 3 is at the low end of the fitter's grid rather than at the top,
which is the opposite of the problem the Kodak colour curves had.

### 3.4 Grain

Page 10 prints one number:

> Diffuse rms Granularity 17
> Read at a net diffuse density of 1.00, using a 48-micrometre aperture, 12X
> magnification.

Seventeen means sigma_D = 0.017. `grain_from_rms.py` turns it into a grain density
from the curve's local slope at the density it was read at — 0.530 per decade at a
net density of 1.0, not γ 0.546, which is the same distinction the colour films
needed. The arithmetic gives 183 grains in the 48 µm aperture's 1,810 µm² at 90
per cent coverage, and **0.1124 grains/µm²**. It is the lowest number in the tree,
which is to say the coarsest grain, and it is what the film is: a 400-speed
conventional emulsion next to T-MAX's tabular one (0.61) and PRO 400H's (2 to 5).

### 3.5 MTF, sensitivity, and the two generators

**MTF.** Page 10 draws one curve for the film, from 2 to 71 cycles/mm read. It
starts above 100 per cent (112 at 10 cycles/mm — the adjacency effect) and falls to
25 per cent. Fitted over 5–60 cycles/mm and 20–100 per cent: **σ 4.06 µm**, rms 0.3
per cent, 54 per cent at 50 cycles/mm against the sheet's 54. The same blur in all
three channels, because a silver image has no colour for it to differ between.

**Sensitivity.** The same page draws two curves, and this section and the file's
header take the more sensitive one — see the section's opening and §5.3 on which
criterion that is. It is 10^log S on the sheet's own scale, on the model's 5 nm
grid. It
peaks near 380 nm (the model grid's first sample; the drawn curve peaks at about
381), falls to a trough at 500, rises to a second hump near 590 and is gone by
660 — the shape Tri-X is known for, and the shape that makes the film's red
response weak and its blue response strong.

**The two generators.** `compile_stocks.py` compiles `NO_DYES` for a monochrome
stock. `pack_film.py` knew only two cases — the stock's own dyes, or a borrow of
VISION3's — and would have written VISION3's three dye curves into a file whose
model says the film has none. That is the third time the same pair of scripts has
disagreed about a fallback (the mask, the grain placeholder, and now the dyes), and
the same fix applies: the packer now makes the branch the compiler makes, and the
file/stock test covers the monochrome film too.

## 4. Results

### Table 1 — the characteristic curve

| layer | base (D-min) | d_max | γ /decade | log_e0 | rates | rms |
|---|---|---|---|---|---|---|
| silver | 0.2618 | 1.4862 | 0.5464 | −0.3957 | 3 / 8 | 0.0049 |

`d_max` is above the base: the absolute asymptote is 0.262 + 1.486 = 1.748. The
same numbers serve all three channels, because the film has one.

### Table 2 — the other measurables

| quantity | value | source |
|---|---|---|
| grain | 0.1124 grains/µm² | page 10, rms granularity 17 at net density 1.0 |
| MTF | σ 4.06 µm | page 10, 5–60 cycles/mm, rms 0.3 % |
| sensitivity | peaks ~381 nm, trough 500, second hump ~590, gone by 660 | page 10 (old 5063 emulsion) |
| at 18 % grey | 0.554 of a density above base | the curve, at log H = −1.44 |
| speed point | 0.52 of a stop late | the curve, against log H = −2.699 |
| dyes, mask | none | a silver image has neither |

### Figures

- `figures/01-curves.png` — the fit and the digitised points, one curve.
- `figures/02-residuals.png` — point minus fit: inside ±0.01 over the drawn range,
  with the family's rise at the far right where the sheet is still climbing.
- `figures/03-spectra.png` — the one sensitivity curve the file carries, normalised
  to its own peak. There are no dye curves and no mask to draw.

## 5. What is measured and what is decided

Measured: the curve, its base, the corner rates, the MTF, the grain number and the
sensitivity — the last two from the previous emulsion, which the sheet states.

Decided:

1. **The 6-minute curve is the stock.** It is the nearest drawn development to the
   sheet's recommended 6¾ minutes.
2. **The ISO relation supplies the anchor.** The sheet prints no `Log H Ref`; the
   relation that predicted all five colour sheets' is used instead.
3. **The more sensitive of the two sensitivity curves.** The legend's swatches are
   crossed and the criterion's direction is the tiebreaker.
4. **The 0.02-density asymptote window**, as on every negative.
5. **Three zero dye rows in the file.** The format has no other way to say "none".

## 6. Uncertainty and limits

The curve panel's calibration is 0.008 of a density in y, and the fit residual is
0.005 — the reading is the larger of the two here, for the first time in the
series.

The grain number is the most model-dependent value in the file: it is one number
inverted through a counting model whose only free input is the curve's local
slope, and a 10 per cent error in that slope is a 10 per cent error in the grain
density. The alternative — inventing a size from a scanned frame — would be a
different measurement, and the sheet's number is the one this project can defend.

The MTF and the sensitivity belong to the previous emulsion. Using them is Kodak's
claim, not this project's measurement, and the file says so in the field that
exists for it.

The speed point is half a stop late and is left out.

## 7. Availability and reproduction

`trix-400.kalofilm` carries the header, the tables and a SHA-256;
`kalo render --film-file` loads it. The figures are regenerated from `curves/`
and the file with

```bash
python3 ../tools/kalofilm.py --check trix-400.kalofilm      # magic, digest, sizes
python3 ../tools/kalofilm.py --csv /tmp/film trix-400.kalofilm
```

`--csv` writes one CSV per table with a wavelength column; the figures in this
report plot exactly those columns (Figure 1: `curves/` against the file's curve;
Figure 2: their difference; Figure 3: the file's layers table), so they can be
redrawn, checked or disagreed with in whatever tool the reader already uses.

The points in `curves/` are in the model's exposure frame — the sheet's log H
shifted by +0.6953 — and carry absolute density, base included. The same 128
points are in all three files; that is what "one record" looks like in a format
whose tables have three channels.

No image of the data sheet is reproduced in this directory.

## References

1. Eastman Kodak Company, *KODAK PROFESSIONAL TRI-X 400 / TRI-X 320*, Japanese
   edition, 2002, printed pages 10 to 12.
2. Kallotype, *The `.kalofilm` format, version 1*, `../FORMAT.md`.
3. Kallotype, *KODAK PROFESSIONAL T-MAX 400* — the compiled stock, for the
   contrast between a tabular-grain emulsion's 0.61 grains/µm² and this film's
   0.11.
