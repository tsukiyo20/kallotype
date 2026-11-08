# KODAK PROFESSIONAL PORTRA 160: the anchor that does not follow the formula

*Kallotype film-data series, report 10 of 21. Version 1, 2026-11-09.
Data: `portra-160.kalofilm` (6,198 bytes). Code: `films/tools/`.*

## Abstract

We digitise KODAK PROFESSIONAL PORTRA 160, a C-41 colour negative, from the four
vector panels on page 4 of E-4051 and release it as a 6.2 kB data file. It is the
slowest film in the Kodak negative family and the best-behaved: its curves fit to
**0.0064 / 0.0042 / 0.0099** of a density, and its base sits within 0.04 of the
sheet's own mask at every layer.

**The anchor.** E-4051 prints `Log H Ref: −1.051`, the only Kodak anchor in the
tree given to three decimals — and it does not follow the family's formula.
`log10(0.8 / S) + 1.26` gives −1.0410 for S = 160; the sheet prints 0.010 lower,
as if its reference had been struck from a speed of 164 rather than 160. The
anchor used is the number the sheet prints, and the discrepancy is recorded
rather than smoothed. The shift is **+0.3063**, against +0.0862 for the corner
midpoint the stock used before: 0.220 decade, 0.73 of a stop, the largest such
gap in the family.

**The fit.** The old fit put each asymptote under the ink — 2.752 against a blue
top of 2.895. `--two-rates --rising --asymptote-window 0.02` bounds it from below
by the highest drawn density; the base lands at 0.212 / 0.628 / 0.842 against
ink floors of 0.210 / 0.625 / 0.844, so this is the closest a fit in the family
comes to reading its base off the chart instead of extrapolating to it. The
residual falls from 0.0156 / 0.0308 / 0.0441 to **0.0064 / 0.0042 / 0.0099**.

**The mask.** The dye panel's lower curve is D-min, which is the model's mask, so
the stock carries its own (**0.836** of a density at 445 nm, 0.168 at the red
end) instead of borrowing VISION3's. The mask's extremes and the fitted bases are
the same three numbers to 0.04. Grain is not claimed: the sheet publishes a Print
Grain Index and says the index cannot be compared to rms granularity.

## 1. Introduction

PORTRA 160 is the fourth film of the Kodak negative family to be re-derived
under the corrected fit and the printed anchor, after PORTRA 400, PORTRA 800 and
EKTAR 100. It is also the least surprising: the same four panels, the same
publisher, the same two-curve dye panel. What it adds is a counter-example — one
number on the sheet that the family rule does not predict — and the cleanest
base-to-mask agreement in the set.

The stock has been in the tree since the colour-negative survey, with the
pre-correction fit and the corner-midpoint anchor. This report replaces it.

## 2. Materials

**The data sheet.** KODAK PROFESSIONAL PORTRA 160 Film, publication E-4051,
revised 2-16 (February 2016), page 4, retrieved 2026-11-08, SHA-256
`a635048f…51c0`. Page 4 carries all four panels; the other three pages carry
exposure tables, a reciprocity table and the Print Grain Index.

**The artwork.** Page 4 is entirely vector: 117 drawing objects, not one embedded
image. The characteristic curves are three paths of **twenty cubic Bézier
segments each** — no straight segments at all — and the axis numbers are
positioned text.

| panel | frame (pt) | axes |
|---|---|---|
| characteristic curves | 185 × 185 | log H −4.0…+1.0, density 0.0…4.0 |
| spectral sensitivity | 200 × 152 | 250…750 nm, log sensitivity 0.0…3.0 |
| spectral dye density | 184 × 184 | 400…700 nm, density 0.0…2.5 |
| modulation transfer | 202 × 153 | 1…600 cycles/mm, 1…100 % (both log) |

Calibration comes from the page's own tick labels: 0.02 log units in x and 0.008
of a density in y on the characteristic panel, 0.01 and 0.007 on the dye panel,
0.00 and 0.002 on the MTF's log axes. The sensitivity panel's y axis prints
`2.0` as `20` — the typesetter dropped the decimal point, and `repair_decimals`
puts it back; the fit's rms falls from 7.5 to 0.006 when it does.

## 3. Methods

### 3.1 The fit: a negative rises

The model's curve is a trapezoid of two softplus corners; fitting it means
choosing the corner positions and rates, after which the two linear parameters
follow exactly. On a reversal the curve falls to a clear-film asymptote and the
fit is bounded by what a transparent material can be. A negative climbs, and the
Kodak sheets stop drawing while it is still climbing, so the asymptote has no
natural bound — which is why the old fit put it under the ink (1.745 / 2.274 /
2.752 against tops of 1.790 / 2.373 / 2.895) rather than draw a top it could not
place.

`--rising` reverses that: the asymptote may not sit below the highest drawn
density, and `--asymptote-window 0.02` keeps it within 0.02 of that point. The
residual falls from **0.0156 / 0.0308 / 0.0441** to **0.0064 / 0.0042 / 0.0099**.

**How much headroom?** A larger window buys almost nothing here:

| window above the drawn top | red | green | blue | rms (r/g/b) |
|---|---|---|---|---|
| 0.02 | 1.801 | 2.391 | 2.906 | 0.0064 / 0.0042 / 0.0099 |
| 0.05 | 1.828 | 2.414 | 2.942 | 0.0052 / 0.0039 / 0.0097 |
| 0.10 | 1.889 | 2.468 | 2.991 | 0.0047 / 0.0035 / 0.0097 |

A tenth of a density of headroom buys 0.0002 to 0.0017 of residual and moves the
asymptote by up to 0.09. It is the least sensitive bound in the family: the blue
layer, which is the one that matters most here, barely moves at all.

**The base.** The fitted bases land at 0.212 / 0.628 / 0.842, and the sheet's ink
bottoms out at 0.210 / 0.625 / 0.844. No other film in the family fits its base
this close to the drawn floor: PORTRA 400's is 0.04 above the ink, EKTAR 100's
blue 0.02, GOLD 200's blue 0.01. It is a property of the artwork as much as of
the fit — this page draws its curves with fine cubics, and the bottom of each
curve is drawn rather than approached.

**The corner rates.** 6/5 for red, 10/10 for green, 6/20 for blue. The blue
shoulder is at the grid's top and the report does not claim it as a measurement.

### 3.2 Reading curves that are drawn in cubics

All three characteristic paths here are built from twenty cubic Bézier segments,
knots about 0.2 decade apart. The reader used to keep only each cubic's end
point, which is a chord through the curve; it now evaluates each cubic at twelve
points. The knots are close on this sheet, so the chord error is under 0.006 of a
density — the smallest of the three sheets re-read in this batch, and the reason
this film's numbers moved by thousandths where EKTAR 100's green curve moved by a
tenth.

### 3.3 The anchor: the sheet prints one, and it is 0.010 off the family's formula

Above the characteristic panel is the line

    Exposure: Daylight   Densitometry: Status M   Log H Ref: −1.051

`Log H Ref` is the log exposure an 18 per cent grey card receives at the film's
rated speed. The model exposes mid grey at log10(0.18) = −0.7447, so the sheet's
axis is shifted by **+0.3063** to put its printed reference there.

**The one number that does not fit.** The four other Kodak anchors in the archive
obey `Log H Ref = log10(0.8 / S) + 1.26` to their last printed digit: −0.84 for
EKTAR 100, −1.14 for GOLD 200, −1.44 for PORTRA 400, −1.74 for PORTRA 800. This
sheet prints three decimals and gives −1.051 where the formula gives −1.0410. The
difference is 0.010 decade, 0.03 of a stop, and it is larger than the rounding of
a three-decimal label can explain: either this sheet used 1.25 as its constant,
or its reference was struck from a speed of 164 rather than the rated 160. The
anchor used is the printed number, because it is the measurement; the mismatch is
recorded rather than replaced by the formula, which is the opposite of what an
earlier draft of the file did.

The stock used to be anchored the other way, on the fitted corner midpoint
(shift +0.0862). The two anchors are 0.220 decade apart, 0.73 of a stop — the
largest gap in the family, and a reminder that a fit-derived anchor moves with
the fit.

**The check.** At the anchor the three records sit 0.628, 0.682 and 0.800 of a
density above their fitted bases. A C-41 negative is balanced for a green-record
density of about 0.70 above D-min at 18 per cent grey; this film reads 0.682, the
lowest in the family, which is what a slower, lower-contrast negative should
read. The anchor lands on the printing aim for the fifth sheet in a row.

**The speed point.** At 1.26 decades below the reference the green record reads
+0.042, so the curve reaches its ISO speed point **0.61 of a stop** later than
the rating — the same offset PORTRA 400 (0.60) and EKTAR 100 (0.67) show, and
unlike GOLD 200 (0.04). It is the sheet's number, it does not move the anchor,
and it is left where the ink puts it.

### 3.4 The mask is this sheet's own

The dye panel is headed *Spectral-Dye-Density Curves* and draws two curves,
labelled **Midscale Neutral** and **Minimum Density**. It does not draw three
dyes, and no Kodak still-film sheet in the archive does; the dye *shapes* stay
borrowed from the VISION3 500T digitisation, and the file's `[measured]` table
says so.

The lower curve is D-min, which is exactly the model's mask — base, fog and the
orange mask as a spectrum. It is read from 400 to 700 nm, put on the model's
380–730 nm grid by repeating the end values (`resample_mask.py`), and it runs
**0.168 to 0.836**, peaking at 445 nm and least at 625. Its extremes agree with
the fitted bases to 0.04, the tightest agreement in the family; the mask has the
same 440–450 nm peak as the other four Kodak negatives, and the lowest absolute
density, which is what a 160-speed film's thinner base looks like.

### 3.5 Sensitivity, MTF, and the grain that is not there

**Sensitivity.** Three vector paths on a 250–750 nm axis, labelled by forming
layer. Stored as `10^logS` on the sheet's own scale, the peaks are 107.9 at
465 nm (yellow-forming, the blue record), 72.4 at 550 (magenta, green) and 100.1
at 625 (cyan, red).

**MTF.** Three vector curves on log axes, one Gaussian per layer over 5–60
cycles/mm and 20–100 per cent response: σ = **4.84, 3.07 and 3.44 µm**. At 50
cycles/mm the model gives 32, 67 and 55 per cent against the sheet's 31, 68 and
55.

**Grain.** The sheet prints a Print Grain Index table and states that the index
"replaces rms granularity and has a different scale which cannot be compared to
rms granularity". There is no rms number on the sheet, so the file carries the
compiled placeholder and says `grain = "placeholder"`. The alternative — inverting
a perceptual index into a grain size — is the kind of number this series exists
not to publish.

## 4. Results

### Table 1 — characteristic curves

| layer | base (D-min) | d_max | γ /decade | log_e0 | rates | rms |
|---|---|---|---|---|---|---|
| red | 0.2117 | 1.5889 | 0.5296 | −0.4340 | 6 / 5 | 0.0064 |
| green | 0.6280 | 1.7632 | 0.5409 | −0.3840 | 10 / 10 | 0.0042 |
| blue | 0.8415 | 2.0647 | 0.6145 | −0.3940 | 6 / 20 | 0.0099 |

`d_max` is above the base: the absolute asymptote is `base + d_max`, and
0.842 + 2.065 = 2.906 is the blue curve's ceiling on the sheet's own axis,
against a drawn top of 2.895. Residuals are against the 128 points in `curves/`.

### Table 2 — the other measurables

| quantity | value | source |
|---|---|---|
| sensitivity peaks | 465, 550, 625 nm | page 4, spectral sensitivity |
| MTF | σ 4.84 / 3.07 / 3.44 µm | page 4, MTF, 5–60 cycles/mm |
| mask | 0.836 at 445 nm → 0.168 at 700 | page 4, D-min |
| dyes | borrowed | VISION3 500T digitisation |
| grain | not claimed | page 3, Print Grain Index |

### Figures

- `figures/01-curves.png` — the fits and the digitised points, all three layers.
  This is the tightest set of fits in the series and the figure shows it: the
  lines and the dots are the same curve at the plot's resolution.
- `figures/02-residuals.png` — point minus fit, inside ±0.01 except at the last
  point of each curve, where the sheet is still climbing and the bounded
  asymptote has begun to flatten.
- `figures/03-spectra.png` — the three layer sensitivities, the three borrowed
  dyes and the film's own mask, as the file carries them.

## 5. What is measured and what is decided

Measured: the three curve shapes, the layer sensitivities, the MTF, the mask, and
the anchor the sheet prints — including the 0.010 that does not follow the
family's formula.

Decided:

1. **The 0.02-density asymptote window.** The model's maximum is the highest
   density the sheet draws; §3.1 shows what a larger window would buy.
2. **The shoulder rates.** The blue shoulder sits at the grid's top and is
   extrapolation beyond the frame.
3. **The mask's ends.** The panel draws 400–700 nm and the grid runs 380–730; the
   ends repeat rather than extrapolate.
4. **The borrowed dyes.** The sheet prints a neutral and D-min, not three dyes.
5. **The unclaimed grain.** The sheet forbids the conversion.

## 6. Uncertainty and limits

The curves are drawn with fine cubics and the residuals are 0.004 to 0.010, at or
near the 0.008 of a density the y calibration can resolve. The asymptote is a
bounded decision; the table in §3.1 shows that a tenth of a density of headroom
is worth 0.0002 to 0.0017 of residual, the least sensitive bound in the family.

The anchor's 0.010 discrepancy is unexplained and is the one open question this
sheet raises. It does not change what the film is: both candidate explanations —
a different constant, or a reference struck from a speed of 164 — move the anchor
by 0.03 of a stop, and the same 0.010 is smaller than the layer-to-layer spread
the fit already carries. It is recorded because the family rule was stated
without exception and this sheet is an exception.

The Bézier reading changed this film's numbers by less than 0.001 of a density.
Every stock read before this batch was digitised with the chord reading; the
straight-segment paths are unaffected, and re-checking the rest is outstanding
work recorded in the research log.

## 7. Availability and reproduction

`portra-160.kalofilm` carries the header, the tables and a SHA-256;
`kalo render --film-file` loads it. The figures are regenerated from `curves/`
and the file with

```bash
python3 ../tools/kalofilm.py --check portra-160.kalofilm      # magic, digest, sizes
python3 ../tools/kalofilm.py --csv /tmp/film portra-160.kalofilm
```

The points in `curves/` are in the model's exposure frame — the sheet's log H
shifted by +0.3063 — and carry absolute Status M density, base included;
`curves/README.md` states the shift so the fit can be recomputed from the sheet's
own axis.

No image of the data sheet is reproduced in this directory.

## References

1. Eastman Kodak Company, *KODAK PROFESSIONAL PORTRA 160 Film*, publication
   E-4051, revised 2-16, page 4.
2. Kallotype, *The `.kalofilm` format, version 1*, `../FORMAT.md`.
3. Kallotype, `films/portra-400/REPORT.md` — the first report that argued the
   printed anchor.
