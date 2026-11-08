# KODAK VISION3 250D: the family baseline, and the chart that will not be read

*Kallotype film-data series, report 16 of 21. Version 1, 2026-11-09.
Data: `vision3-250d.kalofilm` (5,727 bytes). Code: `films/tools/`.*

## Abstract

We digitise KODAK VISION3 250D 5207/7207, an ECN-2 daylight cinema negative,
from the five raster charts on pages 3 and 4 of H-1-5207 and release it as a
5.7 kB data file. It is the family's baseline: the three VISION3 films share a
layout, a dye set and a reader, and this sheet is the one they were built on.

**The charts are rasters.** Every chart, axis number included, is an 8-bit image,
so each is calibrated from its own frame, rules and labels. On this sheet that
costs nothing — its axes are regular — but it is why the family's reports spend
their methods sections on calibration rather than on digitisation.

**Two charts set traps.** The MTF curves run within a pixel of the 100 % rule
from 2 to 25 cycles/mm and merge with it, so continuity tracking cannot follow
them; they are paired by their order in a column instead and read from 25 to
75 cycles/mm. The granularity chart's dashed curves are 83 dots across the whole
plot, against several hundred on the 500T sheet, and the dot tracker loses two of
the three layers — so the grain is the 500T's, declared rather than invented.

The curves, refitted with the series' two-rate rising model, close at **0.0050 /
0.0052 / 0.0055** over 538 points each; the MTF is **4.25 / 3.34 / 3.09 µm**.
Three of the five modelled quantities are borrowed from the 500T digitisation and
the report says what each borrowing costs.

## 1. Introduction

The VISION3 family is the cinema half of this series, and 250D is its daylight
baseline. The three sheets — 50D, 200T and 250D — print the same five charts in
the same arrangement on the same two pages, which makes them the first *family*
in the tree whose members can be compared chart for chart rather than film for
film.

What a cinema negative adds:

- it is rated by an exposure index (250 here) rather than an ISO speed, and its
  exposure axis is **camera stops**, with a separate log-exposure axis above it
  that disagrees with it by about 0.15 decade across the frame;
- its curve has no shoulder. The plot is cut at +8 stops while the density is
  still climbing, so the model's asymptote is an extrapolation;
- its data do not include a published dye set the model can carry — the model
  carries one, and the sheets are checked against it.

## 2. Materials

**The data sheet.** KODAK VISION3 250D Color Negative Film 5207/7207, publication
H-1-5207, four pages, retrieved 2026-11-08, SHA-256 `69094a9c…432799`.

| page | chart | used |
|---|---|---|
| 3 | sensitometric curves | curve and base |
| 3 | modulation transfer | σ per layer |
| 3 | rms granularity | not digitised |
| 4 | spectral sensitivity | three layer responses |
| 4 | spectral dye density | read as a check on the shared set |

**The plots.** Five 8-bit rasters on two pages, each with its frame, rules, ticks
and labels inside the image. Calibration is from the frame and the rules — the
pages print no vector geometry at all — and the errors are quoted per chart in
§3.

## 3. Methods

### 3.1 Reading a raster chart

The reader finds the plot frame as the outermost ruled rectangle, the rules as
evenly-spaced dark rows and columns, and calibrates from those. A curve is
tracked column by column as a dark run; where two curves cross, a two-pixel gap
is bridged by looking ahead one sample. Density is read with the frame's own
scale and log exposure with the camera-stops scale converted to decades.

On this sheet the calibration is exact to a fraction of a pixel on all three
charts used. The 50D sheet's sensitivity labels are the exception that proves the
rule; it is discussed in that report.

### 3.2 The fit

The model's curve is a trapezoid of two softplus corners; the fit chooses the
corners and their rates and solves the two linear parameters exactly. The ink is
cut while the curve is still climbing, so the asymptote is bounded by the highest
drawn density plus the series' 0.02 window, and `d_max` is an extrapolation of
hundredths rather than a reading.

The two-rate fit gives **0.0050 / 0.0052 / 0.0055** over 538 points per layer,
from 0.0050 / 0.0052 / 0.0069 with a single transition: blue gains, red and green
were already at their floor. Rates 4/4 for red and green, 5/4 for blue — the
shoulder sits at the bottom of the grid, which is what a curve cut before its
shoulder must do.

### 3.3 The anchor

The sheet prints no reference exposure. The panel's lower axis is camera stops,
and the model's mid grey sits at log10(0.18) = −0.7447. The curves are anchored
on the printing aim — green at 0.70 of a density above base at mid grey, shift
**+0.5097** — which is the rule PRO 400H uses and the only invariant this sheet
supports. The checks follow: at mid grey the records sit **0.607 / 0.702 / 0.675**
above base, and the speed point lands **0.61 of a stop** slow, at the fast end of
the Kodak colour sheets' 0.60–0.80. Version 1 anchored the corner midpoint
instead, putting mid grey at 0.95; §6 says what that cost.

### 3.4 MTF: the curve that merges with its own 100 % rule

The MTF curves run on a log-log frame from 1 to 600 cycles/mm. Between 2 and 25
cycles/mm they lie within a pixel of the 100 % gridline, so the ink of the curve
and the ink of the rule are the same dark run. Continuity tracking cannot follow
them through that stretch, so the curves are paired by their **order in a
column** — three strokes, read top to bottom, which the labels at their far ends
confirm — and the fit uses 25–75 cycles/mm, where they have separated.

σ = **4.25 / 3.34 / 3.09 µm** for red, green and blue. The 50D's are 4.5 µm and
the 200T's 3.1–4.3, so the family's three sheets order as the ratings do.

### 3.5 Sensitivity, dyes, and the chart that will not be read

**Sensitivity.** Page 4, three layers on a 400–700 nm axis, peaks at **655 / 550
/ 465 nm** with heights 241 / 256 / 296 on the sheet's single `10^logS` scale.

**Dyes.** The panel's three dye curves were digitised and compared with the
compiled 500T tables: the model carries one dye set for the family and this
sheet's agrees with it to 0.12 of a density and 5 nm. The file borrows the 500T
set, declares it, and this comparison is the reason.

**Grain.** The granularity chart plots three solid density curves and three
dashed σ_D curves. The dashed ones are 83 dots across the whole plot — the sheet
draws them as a sparse dash — and the dot tracker finds only two of the three
components. The one layer that could be followed came out at 0.16 grains/µm²
against the 500T's 0.07: the right direction for a slower film, and not enough to
publish. The grain is the 500T's, declared.

**The mask.** The sheet's minimum density is not separated in the granularity
plot, so the file borrows the 500T's mask, as the other two VISION3 films do.

## 4. Results

### Table 1 — characteristic curves

| layer | base | d_max | γ /decade | log_e0 | rates | rms |
|---|---|---|---|---|---|---|
| red | 0.1752 | 1.6713 | 0.4748 | −0.7669 | 4 / 4 | 0.0050 |
| green | 0.5737 | 1.9941 | 0.5570 | −0.7169 | 4 / 4 | 0.0052 |
| blue | 0.8442 | 1.9010 | 0.5370 | −0.7369 | 5 / 4 | 0.0055 |

`d_max` is above the base; the absolute asymptote is `base + d_max`. Residuals
are against the 538 points in `curves/`.

### Table 2 — the other measurables

| quantity | value | source |
|---|---|---|
| sensitivity peaks | 655 / 550 / 465 nm | page 4 |
| MTF | σ 4.25 / 3.34 / 3.09 µm | page 3, 25–75 cycles/mm |
| grain | borrowed: 0.62 / 0.51 / 0.07 | the 500T digitisation |
| dyes | borrowed | one set for the family, agreeing to 0.12 |
| mask | borrowed | the 500T's minimum density |

### Figures

- `figures/01-curves.png` — the fits and the digitised points.
- `figures/02-residuals.png` — inside ±0.01, with the toe's one-pixel staircase.
- `figures/03-spectra.png` — the three sensitivities, the shared dyes and the
  borrowed mask.

## 5. What is measured and what is decided

Measured: the three curve shapes, the layer sensitivities, the MTF, the base.

Decided:

1. **The 0.02 asymptote window**, because the shoulder is outside the frame.
2. **The printing-aim anchor**, because the sheet prints no reference exposure.
3. **The column-order pairing of the MTF curves**, where tracking is impossible.
4. **The shared dye set**, after measuring this sheet's own.
5. **The borrowed grain and mask**, both from charts this sheet does not give up.

## 6. Uncertainty and limits

The curve residuals, 0.0050–0.0055, are at the raster's quantisation; the MTF
fit's own error is larger than the axis calibration (0.3 of a pixel).

The anchor is a decision and the report says so: the sheet prints no reference,
so the film sits where the printing aim puts it. The mid-grey density that
follows (0.61–0.70 above base) is the number a reader could argue with, and it
now agrees with the still films' band. The three VISION3 films were moved
together, so their relative positions are unchanged.

## 7. Availability and reproduction

`vision3-250d.kalofilm` carries the header, the tables and a SHA-256;
`kalo render --film-file` loads it. The figures are regenerated from `curves/`
and the file with

```bash
python3 ../tools/kalofilm.py --check vision3-250d.kalofilm      # magic, digest, sizes
python3 ../tools/kalofilm.py --csv /tmp/film vision3-250d.kalofilm
```

No image of the data sheet is reproduced in this directory.

## References

1. Eastman Kodak Company, *KODAK VISION3 250D Color Negative Film 5207/7207 —
   Technical Data*, publication H-1-5207, pages 3 and 4.
2. Kallotype, *The `.kalofilm` format, version 1*, `../FORMAT.md`.
3. Kallotype, `films/vision3-50d/REPORT.md` and `films/vision3-200t/REPORT.md` —
   the family's other two sheets.
