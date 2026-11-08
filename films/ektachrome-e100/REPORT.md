# KODAK EKTACHROME E100: a second reversal, and the anchor as a measurement

*Kallotype film-data series, report 3 of 3. Version 1, 2026-11-08.
Data: `ektachrome-e100.kalofilm` (5,667 bytes). Code: `films/tools/`.*

## Abstract

We digitise KODAK PROFESSIONAL EKTACHROME E100, an E-6 colour reversal film,
from Kodak Alaris publication E-4000 and release it as a 5.7 kB data file:
three characteristic curves, three dye spectra, three layer sensitivities, a
modulation transfer for each layer, and a grain count inverted from the sheet's
published rms granularity. Two things make this film worth a report beyond
"another stock". Its characteristic panel is drawn as two strokes per side with
no ruling at all, a shape the curve reader had never met, and finding it needed
a rule based on closure rather than on counting rules. And being the second
reversal in the archive, it tests the one decision that a reversal stock cannot
make up: **where 18 % grey sits**. The two sheets answer that question
independently, and they agree to 0.035 decade — one twenty-fifth of a stop
across two manufacturers. The fit residual is the other finding: 0.037, 0.042
and 0.045 of density, in two lobes the model cannot remove because its curve
has one transition for two corners. Splitting the transition drops the same red
curve to 0.012, which is the axis calibration's own floor, and that is a model
change this film proposes rather than performs.

## 1. Introduction

The archive's first reversal, FUJICHROME PROVIA 100F, arrived through a sheet
with an unusual property: its panels were separated ink plates, and two of its
three characteristic curves were incomplete because a plate rasterised from
composited artwork is absent where another ink was painted over it. Everything
about that stock's file is shaped by that defect.

E-4000 is the ordinary case and therefore the useful one. Its charts are vector
paths on a white page, like the KODAK negative sheets the reader was built for,
so the film is read by the same code, fitted by the same fitter, and anchored by
the same rule. If the reversal path in the model only worked for one sheet's
peculiarities, this film would show it.

Two questions are asked of it:

1. **Does the reader cover a sheet that rules nothing?** The characteristic
   panel is bounded by four separate strokes and carries no gridlines. The
   reader reported zero plots on the page, which is indistinguishable from a
   page with no curves.
2. **Does the anchor rule reproduce across manufacturers?** A reversal's 18 %
   grey is a *density*, not the middle of its curve. Both sheets imply an
   absolute exposure at which that density is reached; if the two implications
   agree, the rule is a property of the medium rather than of one sheet's axis.

## 2. Materials

**The data sheet.** Kodak Alaris publication E-4000, revised 8-18, retrieved
2026-11-08, SHA-256 `d6e6fa14…fab6`. The characteristic curves and the
modulation transfer curves are on page 3; the spectral sensitivity and dye
density curves are on page 4.

**The artwork.** Vector paths throughout, with one exception on each page: the
plot borders are strokes rather than rectangles, and the panels sit inside white
boxes. Axis numbers are positioned text outside the frames — unlike the
E-40xx negative sheets, which print theirs inside.

**What the sheet publishes.** Characteristic curves (three, Status A, daylight,
1/100 s); spectral sensitivity (three, log S, 250–750 nm); spectral dye density
(four curves: three dyes normalised to a visual neutral density of 1.0 at
5000 K, and the neutral itself); modulation transfer (three, labelled B, G, R);
diffuse rms granularity (a single value, 8, read at a gross diffuse visual
density of 1.0 through a 48 µm aperture).

## 3. Methods

### 3.1 Finding a plot box that rules nothing

The reader had two ways of finding a plot: a rectangle the PDF records as `re`,
and a box reconstructed from graph-paper ruling — five or more columns standing
the same height. This page has neither. Its borders are four strokes (two
verticals at x 368.7 and 553.9, two horizontals at y 358.6 and 543.0) with no
ruling inside them at all, and its tick marks are three short rules per axis,
which is fewer than the ruling rule's minimum by design.

The new rule is **closure**: two verticals that end where two horizontals run,
within a stroke width, bound a box. It cannot merge two stacked panels, because
their verticals do not share both ends, and it cannot accept a legend swatch,
which is two rules and no box. It is applied after the ruling reader, so the
order of already-known plots on an already-read page does not move.

With the box found, the panel reads normally: five log-exposure labels and five
density labels, and three complete polylines of 57, 61 and 63 segments.

### 3.2 Reading the curves

Each layer is fitted on its own ink by the closed-form fitter: for a fixed
transition and a fixed pair of corner positions the curve is linear in `d_min`
and in amplitude, so the fit is an exact solve over a corner grid rather than a
descent. A reversal's curve falls, which needs no new fitter — the amplitude
simply comes out negative, and `d_min` is the unexposed slide's density.

Two calibrations were compared before the fit was trusted. Reading the density
axis from the printed labels gives 45.6 pt per unit with an rms of 0.017; the
axis's own tick strokes, at 404.7, 450.8 and 496.9, give 46.1 pt per unit and
place 0.0 exactly on the frame's bottom edge. **The labels are up to 4 pt off
their own ticks**, which is 0.09 of density. Refitting on the tick calibration
moved `d_min` by 0.02 and the residual by 0.001: the labels are wrong and it
does not matter here, but the order of trust is the ticks first.

### 3.3 Anchoring the exposure

A negative's 18 % grey is the *middle of its curve*: the exposure of a mid-grey
subject puts the film at the centre of its straight line, and the print stage
then solves for the paper. A reversal has no print stage, so the film's own
placement is the picture. A correctly exposed slide of an 18 % grey card
transmits 18 % of the projector's white — that is, a density of
`d_max + log10(1/0.18)` = `d_max + 0.745`.

So the exposure to solve for is the one at which the red layer's curve reaches
`d_max + 0.745`, and the whole film is then shifted by that amount. The shift is
not a fudge factor: it is the conversion between the sheet's absolute
lux-seconds and the model's relative scene luminance. It comes out at
**+0.2145 decade**.

### 3.4 Spectra

Sensitivities are read as log S, resampled onto the model's 380–730 nm grid at
5 nm, and the tails continued by the slope rule in `spectral_grid.py` — the
drawn paths stop at 393, 473 and 553 nm on the short side, and holding them flat
there would have invented a blue response the sheet does not show. The blue
layer's left tail is at 2.7 % of its peak by 380 nm, which is a statement about
the continuation, not about the film.

The dye panel's three dye paths are resampled on the same grid, unfloored (a
dye's density is linear, not logarithmic), and peak-normalised. The fourth
curve on the panel is the neutral the three make; it is kept as a check and not
carried.

### 3.5 Grain

The sheet publishes one number for the film. It is inverted through the model's
counting statistics at a density of 1.0 through a 48 µm aperture:

    n = (slope / (ln 10 · rms))² / (A · c),  A = 2304 µm², c = 1 − 10^-1 = 0.9

using the mean slope of the three layers, 2.419 per decade, which gives
**8.32 grains/µm²**. The per-layer slopes would have spread that from 7.0 to
9.3; one published number is carried as one number.

## 4. Results

| quantity | red | green | blue |
|---|---|---|---|
| unexposed density `d_min` | 3.348 | 3.729 | 3.909 |
| clear density `d_max` | 0.182 | 0.194 | 0.193 |
| γ (density per decade) | 2.223 | 2.482 | 2.552 |
| inflection, anchored (log E) | −1.194 | −1.242 | −1.318 |
| fit residual (density) | 0.037 | 0.042 | 0.045 |
| σ of the blur (µm) | 5.40 | 4.31 | 3.81 |
| sensitivity peak (nm) | 645 | 545 | 425 |

Dyes: yellow at 445 nm, magenta at 545, cyan at 660 with its red edge still at
0.56 of peak at 730 nm — the widest in the archive. Their raw peaks are 0.935,
0.927 and 0.955, which is what "normalised to a visual neutral of 1.0" predicts,
and the neutral the sheet draws beside them runs from 0.73 to 1.16 across
400–700 nm.

![Characteristic curves: the model's fit as a line, the sheet's digitised points
as dots, one colour per layer. The density is total, because for a reversal it
is the image.](figures/01-curves.png)

![Residuals against the digitised points. The two lobes are the finding: the
model's single transition cannot turn the toe and the shoulder by different
amounts.](figures/02-residuals.png)

![The film's own spectra: layer sensitivities on the log axis the sheet draws
them on, and the three dyes. Both are columns of the shipped file.](figures/03-spectra.png)

## 5. Uncertainty

- **The residual is not noise.** It is ±0.06 of density in two lobes, twice the
  0.017 the axis calibration carries, and it survives every single-transition
  choice (0.035 at t = 3, 0.036 at t = 4, 0.039 at t = 5). Fitting the same red
  curve with independent toe and shoulder transitions gives 0.012 at t = 5 and
  4 — the calibration floor. That is the shape the model cannot express: a
  reversal's toe and shoulder do not turn at the same rate, and one number
  cannot say so. The stock is shipped at t = 4 with the residual reported; the
  two-transition curve is a model change, not a data change.
- **The high-density plateau is extrapolated.** The curves leave the frame at
  `log E` −2.8 still falling, and the ink's own density there is 3.26 to 3.78
  against an asymptote the fit places at 3.35 to 3.91. That is the same order of
  extrapolation as T-MAX 400's shoulder, and for the same reason: a curve that
  reaches its asymptote reads zero slope for half its length, which sheets do
  not draw.
- **The dye panel is normalised, not absolute.** Its ordinate says "normalised
  to a visual neutral density of 1.0"; the model carries shapes, so normalisation
  is the right form, but the *relative* peaks are lost with it. They differ by
  3 %, which is inside the reading error.
- **The grain is one number for three layers**, and its inversion depends on the
  slope used. This is the same route C200 and PROVIA took, with the same caveat.
- **The blue sensitivity has two maxima.** The extraction puts them at 425 nm
  (1.55) and 460 nm (1.30); which one is "the peak" is a matter of 25 nm and
  does not affect any integral the model computes.

## 6. The cross-check that matters

PROVIA's anchor shift, computed from its own sheet, puts its red curve's
inflection at −1.230 in the model's exposure scale. This film's, computed from
its own sheet by the same rule, is −1.194. Two manufacturers, two processes on
either side of the Pacific, two sheets published decades apart, agreeing to
**0.035 decade** — 7 % of a stop.

They also agree about the shape of a reversal: both place 18 % grey near the
shoulder, both fall from a density above 3.3 to a clear film near 0.18, and both
produce a wedge whose ends are 2 and 236 rather than 0 and 255. That agreement
is the strongest evidence in the archive that the anchor rule is about the
medium and not about a sheet.

## 7. What is not done

- **Two transitions per curve.** Section 5 says what it would buy; the model
  has one, and the stock does not pretend otherwise.
- **No push or pull ladder.** Page 3 recommends a one-stop push at 8 minutes in
  the first developer, but publishes no second curve family, so the development
  model is exercised on this stock only at its reference time.
- **No halation data**, as for every stock.
- **The paper it is not printed on.** A slide has no print stage; the render
  shows the film's transmittance and nothing else.

## 8. Availability and reproduction

`ektachrome-e100.kalofilm` carries the header, the tables and a SHA-256;
`kalo render --film-file` loads it, and the compiled stock `ektachrome_e100`
renders byte-identically. The figures are regenerated from `curves/` and the
file with

```bash
python3 ../tools/kalofilm.py --check ektachrome-e100.kalofilm
python3 ../tools/kalofilm.py --csv /tmp/film ektachrome-e100.kalofilm
```

No image of the data sheet is reproduced in this directory.

## References

1. Kodak Alaris, *KODAK PROFESSIONAL EKTACHROME Film E100 — Technical Data*,
   publication E-4000, revised 8-18, pages 3–4.
2. Kallotype, *The `.kalofilm` format, version 1*, `../FORMAT.md`.
3. Kallotype, *FUJICHROME PROVIA 100F*, `../provia-100f/REPORT.md` §4 — the
   anchor rule's first application.
