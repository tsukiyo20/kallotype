# FUJICOLOR SUPERIA X-TRA 400: the bitmap consumer 400

*Kallotype film-data series, report 24 of 24. Version 1, 2026-11-10.
Data: `fuji-superia-xtra400.kalofilm` (6,119 bytes). Code: `films/tools/`.*

## Abstract

FUJICOLOR SUPERIA X-TRA 400 (AF3-0217E) is a consumer colour negative of the
same generation as GOLD 200, and the first stock in the catalogue whose panels
are **bitmaps**. There are no vector paths to walk: every curve was calibrated
against the sheet's own ruled grid and read column by column out of an 800 dpi
raster. The three characteristic curves span log H −3.49…+0.20 on the printed
axis; anchored on the C-41 printing aim they fit at rms **0.0047 / 0.0049 /
0.0061**, with bases 0.127 / 0.459 / 0.745 and γ 0.624 / 0.672 / 0.698.

The sheet publishes an MTF panel, so the blur is measured: **σ = 3.40 µm**, rms
2.6 per cent of response, 58 per cent modelled against the sheet's 57 at 50
cycles/mm. The mask is the sheet's own D-min curve. The dye shapes are borrowed,
because panel 20 prints a mid-scale neutral; grain is **not claimed**, because
the sheet prints no granularity of any kind.

## 1. Materials

**The data sheet.** FUJICOLOR SUPERIA X-TRA 400 — Product Information Bulletin,
publication AF3-0217E, page 6, retrieved 2026-11-10, SHA-256 `7e77f9c3…6a11b2`.

**The panels.** Page 6 draws four:

| panel | content | axis |
|---|---|---|
| 17 | characteristic curves, Blue / Green / Red | log H −4.0…+0.5, density 0…4 |
| 18 | spectral sensitivity, three curves | 380…720 nm, relative log |
| 19 | modulation transfer | 1…200 cycles/mm, 2…150 % |
| 20 | spectral dye density, mid-scale and D-min | 400…720 nm, density 0…2.5 |

Every one of them is a raster. There is no character, no path and no stroke
width to read: the only structure the page has is the ink.

## 2. Methods

### 2.1 What a bitmap costs, and what it does not

A vector panel gives up its curves as polylines with coordinates attached. A
bitmap gives up pixels, and the work moves into three problems.

**The axes.** The sheet rules its grid every 0.5 in log H and every 0.5 in
density. Those rules are the calibration: ten vertical ones and nine horizontal
ones on panel 17, fitted by least squares, giving **0.0085 of a log H** and
**0.0095 of a density** of residual — the raster's own quantisation at 800 dpi.
A first pass calibrated off the printed tick labels instead and was 0.02 out in
both, because a label's centroid is biased by its minus sign. The grid is the
axis; the label only says what to call it.

**The text.** The legend sits inside the plot, the three curve labels sit between
the curves, and the caption sits over the top right. All of it is ink. Text is
removed by what it is: a letter is a small mark. After the rules are erased, the
image is labelled into connected components and a component is kept only if it
is **long in one direction or the other** — wider than 500 px or taller than
300. A caption line is wide and short and goes; the steep lower flank of a
sensitivity curve is narrow and 600 px tall and stays. The first version tested
width alone and deleted every rising edge on panel 18, which reads in the output
as three curves that all begin at their peaks.

**The crossings.** Panel 18's three curves intersect. A tracker that steps
column by column and takes the nearest run swaps onto the neighbour at every
crossing — both choices are one stroke wide at that point, and a local rule has
nothing to prefer. The curves are therefore followed as a shortest smooth path:
a state is the curve's height in a column, a transition costs the squared
deviation from the straight line the previous two columns predict, and the path
is chosen over the whole panel at once. Two curves crossing at an angle offer
one continuation that bends and one that does not.

Two smaller traps, both found by looking at the output rather than at the code.
A curve crossing a rule at a shallow angle is cut by the erasure into two runs
nine pixels apart, which reads as four curves in a column — the runs are merged
again across a gap. And the run-height filter that rejects a text glyph also
rejects a curve, because a stroke six pixels thick spanning a column at a slope
of two is twenty-nine pixels tall: the limit is now four times the stroke, not
double.

### 2.2 The curves

Each layer is fitted with `fit_stock_curve.py --two-rates --rising
--asymptote-window 0.02` over the 1545 digitised columns, resampled to 0.02 of a
decade first:

| layer | base | d_max | γ /decade | log_e0 | rates | rms | ink floor |
|---|---|---|---|---|---|---|---|
| red | 0.1266 | 1.8706 | 0.6235 | −0.2814 | 3 / 16 | 0.0047 | 0.148 |
| green | 0.4593 | 2.0299 | 0.6722 | −0.2714 | 5 / 16 | 0.0049 | 0.462 |
| blue | 0.7453 | 2.0795 | 0.6978 | −0.2514 | 8 / 16 | 0.0061 | 0.736 |

Three things in that table are the sheet's, not the fitter's. The bases land
within 0.022 of the density the ink actually bottoms out at. The toe rates rise
with the layer's speed — 3, 5, 8 — which is what a colour negative's masks do to
its low end. And **all three shoulders want the top of the rate grid**, 16 per
decade, because the sheet stops drawing while every curve is still climbing: at
the last column the blue record is at 2.812 and rising at 0.7 of a density per
decade. The asymptote is a floor under the ink's top, not a measured plateau,
and the file says so rather than quoting the number as a shoulder.

### 2.3 The anchor

AF3-0217E prints no reference exposure. It labels the axis absolute — "log H
(lux-seconds)" — and on that axis the green record reaches D_min + 0.15, the
ISO 5800 speed point, at −2.665: within 0.04 of a decade of where ISO 400 puts
it. So the drawing is consistent with the rating it prints.

It is still not the frame the model uses. Mid grey is log10(0.18) = −0.7447
there, and an 18 per cent card at ISO 400 receives about −1.70 absolute. The
anchor taken is the one every measured colour negative in the tree takes — mid
grey where the green record sits 0.70 of a density above its base — which is
**shift +1.0291**. In the model's frame the film then reaches its speed point
**0.36 of a stop early**, against the Kodak sheets' 0.60–0.78 and PRO 400H's
0.87. It is the tightest anchor in the series and it is still, deliberately, a
printer's decision rather than the sheet's own statement, because the sheet does
not make one.

### 2.4 The sensitivities

Panel 18 draws the three curves against a relative log axis with no numbers on
it, but with a double-headed arrow marked "1.0" between two of its own grid
rules. That arrow is the scale: it spans one grid interval, so one decade is
634 px, and the curves are read in decades and exponentiated.

The drawing stops each curve a fixed distance below its peak, and the peaks are
not at the same height: they are 0.09 and 0.22 of a decade apart. On a relative
axis that difference carries no absolute meaning, so the three are kept as drawn
and scaled by the tallest, the way PRO 400H's are:

| layer | peak | at | decay to 1/e |
|---|---|---|---|
| blue-sensitive (yellow) | 1.00 | 470 nm | 400–507 nm drawn |
| green-sensitive (magenta) | 0.83 | 555 nm | 495–600 nm drawn |
| red-sensitive (cyan) | 0.49 | 640 nm | 583–678 nm drawn |

### 2.5 The mask and the dyes

Panel 20 draws one mid-scale neutral and one minimum density. The D-min curve is
the mask: this film's own base, fog and orange mask, 0.911 of a density at
400 nm falling to 0.209 at 730. It is measured, and the spectral print reads it.

The three dyes are **not** in the sheet — a mid-scale neutral is their sum at
one exposure, not three curves — so the dye shapes are borrowed from the VISION3
500T digitisation, exactly as for ULTRA MAX 400 and GOLD 200. The sheet's own
neutral is kept alongside in `private/data/dyes/superia_xtra400_midscale.csv` as
the check on what the borrowed dyes produce: it peaks at 1.95 at 450 nm, troughs
at 1.08 near 600 and rises again to 1.77 at 700.

### 2.6 The blur

Panel 19 is logarithmic on both axes, 1–200 cycles/mm and 2–150 per cent, with
one curve for the film. Its plateau sits at **115 per cent**, which no transfer
function can do — it is the adjacency effect, the developer exhausting itself
around a fine edge and leaving the film more contrasty than the subject. The fit
is therefore held to 20–100 per cent of response over 5–60 cycles/mm, and gives
**σ = 3.40 µm**, rms 2.6 per cent of response, the model reading 58 per cent at
50 cycles/mm against the sheet's 57.

### 2.7 What is not measured

**Grain.** AF3-0217E publishes no granularity figure of any kind — not rms
granularity, not a Print Grain Index, not a table. No scan of this stock was
available to measure one from. The field is zero and the note says why: a number
chosen to fill the slot would be indistinguishable, downstream, from the ones
TRI-X and DELTA 400 measured.

## 3. Results

### Figures

- `figures/01-curves.png` — the fit and the 128 exported points, per layer.
- `figures/02-residuals.png` — point minus fit. The raster's stair-steps show
  as spikes of up to 0.02 of a density where a column's run centroid moves by a
  pixel, and the last two thirds of a decade roll upwards because the model's
  asymptote is a floor under ink that the sheet left still climbing.
- `figures/03-spectra.png` — the three measured sensitivities, the measured mask
  and the borrowed dyes, all as the file carries them.

### At a glance

| | red | green | blue |
|---|---|---|---|
| base density | 0.127 | 0.459 | 0.745 |
| γ per decade | 0.624 | 0.672 | 0.698 |
| log_e0 | −0.281 | −0.271 | −0.251 |
| fit rms | 0.0047 | 0.0049 | 0.0061 |
| sensitivity peak | 0.49 | 0.83 | 1.00 |

## 4. What is measured and what is decided

Measured: the three characteristic curves, the three spectral sensitivities, the
minimum-density curve and the modulation transfer function — four of the six
panels' worth, all of it from the sheet's own ink.

Decided:

1. **The printing-aim anchor**, because the sheet prints no reference exposure.
   §2.3 gives the error it leaves: 0.36 of a stop.
2. **The shoulder rate at the grid's ceiling**, because the drawing ends before
   the curves do.
3. **Borrowed dye shapes**, because a mid-scale neutral is not three dyes.
4. **No grain at all**, because the sheet measured none and no scan here could.

## 5. Availability and reproduction

`fuji-superia-xtra400.kalofilm` carries the header, the tables and a SHA-256;
`kalo render --film-file` loads it.

```bash
python3 ../tools/kalofilm.py --check fuji-superia-xtra400.kalofilm
```

No image of the data sheet is reproduced in this directory, and the digitisation
scripts that read it are not published either: they are working tools, and the
points they produce are here.

## References

1. Fuji Photo Film Co., *FUJICOLOR SUPERIA X-TRA 400 — Product Information
   Bulletin*, publication AF3-0217E, page 6.
2. Kallotype, `films/gold-200/REPORT.md` — the 200-speed sheet of the same
   drawing system.
3. Kallotype, `films/kodak-ultramax-400/REPORT.md` — the sheet that prints a
   reference exposure this one does not.
