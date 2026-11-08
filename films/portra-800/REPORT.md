# KODAK PROFESSIONAL PORTRA 800: an axis printed out of order

*Kallotype film-data series, report 6 of 16. Version 1, 2026-11-08.
Data: `portra-800.kalofilm` (6,358 bytes). Code: `films/tools/`.*

## Abstract

We digitise KODAK PROFESSIONAL PORTRA 800, a C-41 colour negative, from the six
vector panels on pages 4 and 5 of E-4040 and release it as a 6.4 kB data file. It
is the second Kodak negative in this series, and two things about its sheet are
new.

**The axis is printed out of order.** The EI 800 panel labels its log exposure
axis −4.0, −2.0, −3.0, −1.0, 0.0, 1.0: the second and third labels are swapped.
It is a typesetting slip in the PDF, not a reading error — the rendered page
shows it — and no assignment of signs makes the digits monotone, so no reader can
repair it by inference. What does repair it is the *tick marks*: three interior
ticks, evenly spaced at 36.9 pt, inside a frame 184.6 pt wide, which is exactly
five decades across. The ticks say where −4, −3, −2, −1, 0 and +1 are, and the
labels are wrong about it. Both axes on this sheet are therefore stated from
geometry rather than read from text, and the density axis gains from that too:
its labels jitter by up to 0.05 of a density while its ticks are exact.

**The sheet draws development three times.** Printed page 4 carries three
characteristic-curve panels — EI 800, EI 1600 (Push 1) and EI 3200 (Push 2) — of
the *same* exposure developed three ways. It is the first sheet this series has
read that draws one film at three exposure indices, side by side, and the
contrast rises monotonically on every layer: γ 0.521 → 0.631 → 0.688 (red),
0.534 → 0.638 → 0.738 (green) and 0.608 → 0.731 → 0.789 (blue). The stock uses
the EI 800 panel; the other two are kept as the check the model's development
kinetics will be held to.

The anchor is the sheet's printed `Log H Ref: −1.74` — the same relation E-4050
uses at −1.44, evaluated at ISO 800. At that exposure the green record sits 0.687
of a density above D-min, where a C-41 negative is balanced to print. The dye
panel's lower curve gives the film its own mask (**0.86** at 380 nm, 0.26 at
650) instead of VISION3's, and the fit residuals are **0.0026, 0.0035 and
0.0038** — the tightest average in the series. Grain is not claimed: the sheet
prints a Print Grain Index and says it cannot be compared to rms granularity.

## 1. Introduction

PORTRA 800 is the fast member of Kodak's professional negative family, and its
sheet is the first in this archive that answers a question the model asks
directly: what does development *do* to the curve? E-4050, E-4046 and E-7022 each
draw one curve family. E-4040 draws three, side by side, at the three exposure
indices the film is sold for, and the difference between them is development.

The reading problem is different too. The previous sheet in this series made the
fitter admit that a negative rises; this one makes the reader admit that the
page can be wrong about its own numbers.

## 2. Materials

**The data sheet.** KODAK PROFESSIONAL PORTRA 800 Film, publication E-4040,
revised 2-16 (February 2016), retrieved 2026-11-08, SHA-256 `9482510d…330b7b9`.
Printed page 4 carries the three characteristic panels and the spectral
sensitivity; printed page 5 carries the dye panel and the MTF. All six are vector
paths: the page has 62 and 84 drawing objects and no embedded image on either.

| panel | frame (pt) | axes |
|---|---|---|
| characteristic, EI 800 | 184.6 × 184.4 | log H −4…+1, density 0…4 |
| characteristic, EI 1600 | 184.5 × 184.4 | same |
| characteristic, EI 3200 | — | same, but the frame the reader finds is not the plot box |
| spectral sensitivity | — | 250…750 nm, log sensitivity 0…4 |
| spectral dye density | 184.3 × 184.3 | 400…700 nm, density 0…2.5 |
| modulation transfer | — | 1…600 cycles/mm, 1…200 %, both log |

The frames marked "—" are the ones whose detected rectangle is not the plotting
box; the label fit is used there and its residuals are stated below.

## 3. Methods

### 3.1 The axis that is wrong, and the ticks that are right

The EI 800 panel's log H labels, in the order the page positions them, are

    -4.0   -2.0   -3.0   -1.0   0.0   1.0

Read as text, that is not an axis: no sign assignment makes `4, 2, 3, 1, 0, 1`
monotone, and a reader that sorts the labels by position produces a mirrored
axis with a kink in it. The first attempt at this sheet did exactly that and the
fit paid 0.032–0.040 of a density for it.

The panel also draws tick marks: four short rules at
x = 118.53, 155.46, 192.35 and 229.28 pt, spaced 36.9 pt apart,
inside a frame from 81.6 to 266.2. Five decades across 184.6 pt is 36.92 pt per
decade, so the ticks are −3, −2, −1 and 0, the frame's left edge is −4 and its
right edge is +1. The labels sit on those ticks to within 2 pt and carry the
wrong digits: the tick at 118.53 is labelled −2.0 and the tick at 155.46 is
labelled −3.0. The page is wrong and the geometry is right, and the geometry wins.

The density axis has the same construction and the same lesson, without the
defect. Its three ticks are at y = 212.80, 166.71 and 120.56, spaced 46.1 pt, and
the frame's bottom is at 258.9 and its top at 74.5 — which puts 0.0 exactly on the
bottom, 4.0 on the top and 1, 2, 3 on the ticks. Its *labels*, by contrast, sit
up to 2 pt (0.045 of a density) off their ticks. So the density axis is stated
from the frame and the ticks as well, and the x and y residuals of that decision
are zero and 0.008.

Both axes stated means the panel's numbers are geometry, not text. The other two
characteristic panels are stated the same way; their ticks give the same 46.1 pt
per unit.

### 3.2 The fit, and the third time it has mattered

The curves climb to the right-hand edge of their frames, like every Kodak
negative's, so the fit uses `--rising --asymptote-window 0.02`: the asymptote may
not sit below the highest density the sheet draws, and may go at most 0.02 above
it. The fit before this one was made without that bound and put the red
asymptote at 1.867 where the ink reaches 1.935 — 0.07 of a density low — with the
same shortfall on green and blue, and settled at 0.032/0.028/0.040.

With the bound the residual is **0.0026 / 0.0035 / 0.0038** — the tightest average
of the six films, and well under the 0.008 of a density the calibration itself
carries. The corner rates are 5/16 for red, 8/8 for green and 5/20 for blue; all
three shoulders sit outside the drawn frame, so those rates are the family's
usual extrapolation even where the two corners agree.

### 3.3 The anchor

`Log H Ref: −1.74` is printed on all three characteristic panels and is the log
exposure an 18 per cent grey card receives at EI 800:
log10(0.8/800) + 1.26 = −3.00 + 1.26 = −1.74. The model exposes mid grey at
log10(0.18) = −0.7447, so the sheet's axis is shifted by **+0.9953** for every
layer.

**The check.** At that exposure the three records sit 0.600, 0.687 and 0.706 of a
density above their minima (red, green, blue). The green record is where a C-41
negative is balanced to print, and it arrived there from the sheet's printed
number. PORTRA 400's sheet gave 0.705 by the same route; two sheets at different
speeds landing on the same aim is the strongest evidence in the series that the
`Log H Ref` convention is the right one.

**The check that still does not close.** At the nominal speed point
(log H = −3.00, 1.26 decades below the reference exposure) the green record reads
+0.056 where ISO 5800 asks for +0.10. The drawn curve reaches the speed point
0.44 of a stop later than its rating, where PORTRA 400's sheet is 0.60 late, and
for the same reason. It is the sheet's, it is consistent across the family, and
it does not move the anchor, which is the reference exposure and not the speed
point.

### 3.4 The development ladder

The three characteristic panels are the same film, the same exposure and the same
densitometry, developed three ways. Fit with the same routine in the sheet's own
frame — so the EI 800 numbers here differ from Table 1 by the anchor shift, which
does not change any difference between panels:

| panel | γ red | γ green | γ blue | rms (r/g/b) |
|---|---|---|---|---|
| EI 800 | 0.521 | 0.534 | 0.608 | 0.0026 / 0.0035 / 0.0038 |
| EI 1600 (push 1) | 0.631 | 0.638 | 0.731 | 0.0047 / 0.0121 / 0.0083 |
| EI 3200 (push 2) | 0.688 | 0.738 | 0.789 | 0.0069 / 0.0135 / 0.0104 |

Every layer gains contrast at every rung, and the gain is larger on the first
than on the second: +0.11/+0.06 (red), +0.10/+0.10 (green), +0.12/+0.06 (blue).
The second rung's larger residuals are the drawing's: the pushed curves are
steeper and shorter, and a two-corner model follows them a little less closely.

This is a ladder of *development states*, not of exposure times: the sheet uses
one exposure axis for all three panels, and the difference is the process. The
development times that produce them are in the development tables elsewhere on
the sheet and are not read here. When this report was written the model's
kinetics had never been checked against a manufacturer's ladder; the check was
run the same day on TRI-X 400's four-time D-76 family, a ladder whose rungs have
times rather than exposure indices, and it moved the model's fog, ceiling, speed
and toe constants from priors to measurements. This film's two panels are the
colour equivalent and are kept for the same purpose.

### 3.5 Sensitivity, dye panel, MTF, grain

**Sensitivity.** Three vector paths on 250–750 nm, drawn only across their own
bands and labelled Yellow-, Magenta- and Cyan-Forming Layer in place. Peaks 410,
545 and 655 nm at 10^log S = 533, 703 and 843 on the sheet's own scale. The
digitisation reproduces, value for value, the curves the tree already carried —
this is the one panel of the six that is a re-read rather than a new reading, and
it agreed to the last stored digit.

**Dye panel.** A mid-scale neutral and D-min, the family's usual pair, with
"Minimum Density" beside the lower curve. D-min is the model's mask: read from
400 to 700 nm at 5 nm and put on the 380–730 grid by repeating the end values.
The curve was re-read on 2026-11-09, when the vector reader learned to sample
cubic Béziers rather than their end points: the mask moved by at most **0.062**
of a density at 430 nm — the yellow-mask bump, where the drawing's curvature is
highest — and by 0.016 rms, and the numbers above are the re-read ones. This is
the one place the old reading was materially wrong in the shipped films.
The family's base densities now read 0.217/0.651/0.865 at ISO 400 and
0.302/0.705/1.011 at ISO 800 — the mask thickens with speed, which is the one
place the two sheets agree without being told to.

**MTF.** Three vector curves on log-log axes, R/G/B in the order their letters
terminate beside them. One Gaussian per layer over 5–60 cycles/mm and 20–100 per
cent: σ = **4.75, 3.69 and 3.00 µm**, rms 5.3, 2.0 and 0.8 per cent. At 50
cycles/mm the fit and the sheet both read 30, 57 and 67 per cent, the closest
agreement at that frequency in the series.

**Grain.** E-4040 prints the same Print Grain Index table and the same sentence
as E-4050: the index "replaces rms granularity and has a different scale which
cannot be compared to rms granularity". No rms number, no grain parameter; the
file carries the compiled placeholder and its `[measured]` line says so.

## 4. Results

### Table 1 — characteristic curves at EI 800

| layer | base (D-min) | d_max | γ /decade | log_e0 | rates | rms |
|---|---|---|---|---|---|---|
| red | 0.3022 | 1.6477 | 0.5214 | −0.3254 | 5 / 16 | 0.0026 |
| green | 0.7051 | 1.7178 | 0.5335 | −0.4154 | 8 / 8 | 0.0035 |
| blue | 1.0107 | 1.9572 | 0.6078 | −0.3154 | 5 / 20 | 0.0038 |

`d_max` is above the base, as the model's curve is; the absolute asymptote is
`base + d_max`, so 0.302 + 1.648 = 1.950 is the red curve's ceiling. Residuals
are against the 128 points in `curves/`.

### Table 2 — the other measurables

| quantity | value | source |
|---|---|---|
| sensitivity peaks | 410, 545, 655 nm | page 4, spectral sensitivity |
| MTF | σ 4.75 / 3.69 / 3.00 µm | page 5, 5–60 cycles/mm |
| mask | 0.863 at 400 nm → 0.996 at 430 → 0.228 at 650 | page 5, D-min |
| dyes | borrowed | VISION3 500T digitisation |
| grain | not claimed | page 3, Print Grain Index |

### Figures

- `figures/01-curves.png` — the fits and the digitised points, all three layers.
- `figures/02-residuals.png` — point minus fit. Inside ±0.01 over the drawn
  range, with the family's usual rise at the far right where the sheet is still
  climbing and the model has begun to flatten. That rise, at the last point of
  each curve, is most of what the rms is made of.
- `figures/03-spectra.png` — the three layer sensitivities, the three borrowed
  dyes and the film's own mask, as the file carries them.

## 5. What is measured and what is decided

Measured: the three plateaus, the three speeds, both corner rates, the layer
sensitivities, the MTF and the mask. The anchor is the sheet's printed number and
the shift follows from it by arithmetic. The two pushed families are measured
too, and are not part of the file.

Decided:

1. **Both axes stated from geometry.** The log H axis because the labels are
   wrong, the density axis because the ticks are better than the labels. §3.1
   prices it: x residual 0.00, y residual 0.008 of a density.
2. **The 0.02-density asymptote window.** The sheet does not draw the shoulder in
   any of the three panels.
3. **The EI 800 panel is the stock.** EI 1600 and EI 3200 are the same film
   developed further, and a stock is one development.
4. **The mask's ends.** 400–700 nm drawn, 380–730 gridded, the ends repeated.
5. **The borrowed dyes.** The sheet prints a neutral and D-min, not three dyes.
6. **The unclaimed grain.** The sheet forbids the conversion.
7. **The residual at the top of each curve.** Reported, not fitted away with a
   larger asymptote window.

## 6. Uncertainty and limits

The readings are geometric: the ticks are the page's own construction and the
curves are its paths, so the digitising error is the resampling, not a pixel.
What the calibration contributes is 0.008 of a density on the stated axis, which
is the same order as the fit residual on the green layer and larger than it on
the other two.

The three panels do not agree on their own base densities to better than about
0.05 of a density, and their labels are placed to about 0.045. That is the floor
under any comparison *between* the panels: the ladder's contrast differences
(0.06–0.12) are well above it, but its density differences at a fixed exposure
are not.

The asymptote is bounded by a decision rather than measured, exactly as on
PORTRA 400; the window table there shows the sensitivity.

The speed check is a third of a stop out, as on PORTRA 400, and is left out for
the same reason.

## 7. Availability and reproduction

`portra-800.kalofilm` carries the header, the tables and a SHA-256;
`kalo render --film-file` loads it. The figures are regenerated from `curves/`
and the file with

```bash
python3 ../tools/kalofilm.py --check portra-800.kalofilm      # magic, digest, sizes
python3 ../tools/kalofilm.py --csv /tmp/film portra-800.kalofilm
```

`--csv` writes one CSV per table with a wavelength column; the figures in this
report plot exactly those columns (Figure 1: `curves/` against the file's curves;
Figure 2: their difference; Figure 3: the file's tables), so they can be redrawn,
checked or disagreed with in whatever tool the reader already uses.

The points in `curves/` are in the model's exposure frame — the sheet's log H
shifted by +0.9953 — and carry absolute Status M density, base included. The
shift is stated in `curves/README.md`. The EI 1600 and EI 3200 points are not
shipped: they are not part of the film this file describes.

No image of the data sheet is reproduced in this directory.

## References

1. Eastman Kodak Company, *KODAK PROFESSIONAL PORTRA 800 Film*, publication
   E-4040, revised 2-16, pages 4 and 5.
2. Kallotype, *The `.kalofilm` format, version 1*, `../FORMAT.md`.
3. Kallotype, *KODAK PROFESSIONAL PORTRA 400: the negative that rises*,
   `../portra-400/REPORT.md` — the same `Log H Ref` anchor at ISO 400.
