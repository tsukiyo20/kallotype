# KODAK PROFESSIONAL T-MAX 400: the film that borrows nothing

*Kallotype film-data series, report 12 of 16. Version 1, 2026-11-09.
Data: `tmax-400.kalofilm` (5,769 bytes). Code: `films/tools/`.*

## Abstract

We digitise KODAK PROFESSIONAL T-MAX 400, a black-and-white negative, from
F-4043 — the sheet that carries the curve, the MTF, the granularity and the
spectral sensitivity on four of its twelve pages — and release it as a 5.8 kB
data file. It is the third silver film in the series and the first film in it
with **nothing borrowed**: no dyes and no mask, because a silver image has
neither, and no quantities taken from another stock or another sheet.

**The axis is absolute, and this file used to ignore it.** Page 9 prints
`LOG EXPOSURE (lux-seconds)` from −4.0 to +1.0. The first derivation fitted the
digitised points on that axis and left them where the sheet put them, which
places mid grey at the printed −0.745 instead of the −1.44 an 18 per cent grey
card receives at ISO 400 — a 2.3-stop error in where the film's curve sits
relative to the scene. The shift is **+0.6953**, and the check that it is the
right one is the film's own speed: shifted, the curve reaches D_min + 0.10
within **0.18 of a stop** of its ISO 400 rating, the same test TRI-X's sheet
closes to 0.10.

**The shoulder is outside the frame.** The ink stops at a density of 2.151 while
the curve is still climbing. The first derivation continued its straight line to
an asymptote of 2.626 — the file called that a fit rather than a reading. The
series' rule bounds it by the highest drawn density, which gives **2.168**, and
the report's window table shows that forty times the window buys 0.0005 of rms.

**The grain is one number.** Page 8 prints a diffuse rms granularity of 10 at a
net density of 1.00 through a 48 µm aperture; inverted at the curve's local
slope it is **0.6079 grains/µm²**. With the 2.79 µm MTF this is the sharpest and
finest-grained film in the series, and the first whose grain number comes from a
manufacturer rather than from scans.

## 1. Introduction

The series' two silver films came with holes. TRI-X's sheet publishes MTF and
sensitivity for the **old 5063 emulsion** and says so; HP5's publishes one chart
in six pages and the file declares four absences. T-MAX 400 is the first Kodak
silver sheet built the way the colour sheets are — a curve panel with three
development times, an image-structure page, an MTF and a two-density sensitivity
plot — and the first film whose five modelled fields are all measured.

It is also the first where the model's own conventions had to give: a
monochrome film has one record and the format has three channels, and its grain
is a differential measurement rather than a curve.

## 2. Materials

**The data sheet.** KODAK PROFESSIONAL T-MAX 400 Film Technical Data,
publication F-4043, October 2007, twelve pages, retrieved 2026-11-08, SHA-256
`55b1028c…c33f75`. It is a text-layer PDF, not a scan; the charts are line art
on ruled frames.

| page | what it carries | used |
|---|---|---|
| 8 | image-structure table: resolving power, diffuse rms granularity | grain |
| 9 | characteristic curves in four panels, three times each | curve |
| 10 | contrast-index curves, seven developers by time | not used |
| 11 | modulation transfer function and spectral sensitivity | MTF, layers |

**The curve panel.** Page 9's first panel is D-76 in a small tank at 20 °C,
drawn for **6, 8 and 11 minutes** in three line styles that converge into a
single stroke at the toe. Eight minutes is the panel's middle curve and the time
the rest of the sheet is written around, so it is the reference development:
`--dev 8 --temp 20` is the sheet's curve and any other setting is a deliberate
move away from it.

## 3. Methods

### 3.1 Reading three curves that merge at the toe

This is the hardest curve panel in the series: three curves in one frame, in
three line styles, that become one line at the bottom. `extract_tmax400.py`
separates them by **connected-component size** — the solid curve is one large
blob, the dashed and dotted ones arrive as dozens of small ones — and where the
reproduction has actually merged the strokes it shares a single reading and says
so. 400 points, about 0.010 decades apart.

Each of the three is fitted and kept. The **eight-minute** curve is the one
compiled; the six- and eleven-minute curves are the development ladder the
model's kinetics are checked against and are not compiled.

### 3.2 The fit and the shoulder outside the frame

The model's curve is a trapezoid of two softplus corners; fitting it means
choosing the corners and their rates, after which the two linear parameters
follow exactly. For a negative the curve climbs, and this sheet stops drawing at
a density of 2.151 while the curve is still rising, so the top is not measured.

The first derivation continued the straight part of the curve and put the
asymptote at 2.626 — 0.47 of a density above anything the sheet drew — and said
in its own note that this was a fit and not a reading. The series' rule is the
opposite: the model's maximum is the highest density the sheet draws, plus a
0.02 window, which gives **2.168**. The rule costs almost nothing here:

| window above the drawn top | asymptote | rms |
|---|---|---|
| 0.02 | 2.168 | 0.0110 |
| 0.10 | 2.249 | 0.0106 |
| 0.40 | 2.372 | 0.0105 |

Forty times the window buys 0.0005 of residual. The asymptote is unmeasured
either way; the rule makes it unmeasured in the same direction as every other
film in the series.

The fit chooses rates 2.5 at the toe and 10 at the shoulder, γ 0.728 per decade,
and a residual of **0.0110** over 400 points — twice the colour films' 0.004,
which is the raster digitisation and not the curve.

**The base.** The fit's asymptote under the toe, 0.2168, against an ink floor of
0.2266. A silver negative's curve begins at base plus fog, and the model wants
the silver above the base with the base carried separately.

### 3.3 The anchor: an absolute axis that can be checked

Page 9 prints `LOG EXPOSURE (lux-seconds)` from −4.0 to +1.0. An 18 per cent
grey card at ISO 400 receives `log10(0.8/400) + 1.26 = −1.4398` on that axis, and
the model exposes mid grey at `log10(0.18) = −0.7447`, so the points are shifted
by **+0.6953**.

Unlike the printed references, this anchor can be checked against the film's own
speed, because the axis is absolute: the ISO 5800 speed point is where the curve
reaches D_min + 0.10, and that must sit 1.26 decades below the reference. The
digitised curve reaches it at −1.949 after the shift, against a required
−2.0047 — **0.18 of a stop** slow, where TRI-X's absolute-axis sheet closes to
0.10 and the Kodak colour sheets sit 0.6 to 0.8 slow. The first derivation did
not apply the shift at all: it fitted the curve on the sheet's axis and left mid
grey at −0.745, which put the model's speed point 2.2 stops away from the film's.

### 3.4 Granularity, MTF, and the sensitivity of a silver image

**Grain.** Page 8 prints one number: "Diffuse rms Granularity 10", footnoted
"read at a net diffuse density of 1.00, using a 48-micrometre aperture, 12X
magnification". Ten in that table is σ_D = 0.010, and `grain_from_rms.py` inverts
it at the curve's local slope to **0.6079 grains/µm²** — the same counting
arithmetic the VISION3 charts are inverted with, and the first grain number in
the series taken from a manufacturer rather than from scans.

**MTF.** Page 11, one curve on log-log axes from 2.5 to 79 cycles/mm, fitted over
5–60 cycles/mm to a single Gaussian: σ = **2.79 µm**, rms 2.0 per cent of
response, reproducing the sheet's 74 per cent at 50 cycles/mm to within a point.
A silver image has one record, so all three channels carry it.

**Sensitivity.** Page 11 prints two curves, at D = 0.3 and D = 1.0 above D-min.
The model has one response, so the D = 0.3 curve is carried, digitised from
360 to 647 nm: **peak 570 nm**, half its peak at 400 and 600, nothing beyond 645.
Beyond the last measured wavelength the grid is zero rather than held, because
the film has no sensitivity left to plot and a held tail would invent one.

## 4. Results

### Table 1 — the characteristic curve

| layer | base | d_max | γ /decade | log_e0 | rates | rms |
|---|---|---|---|---|---|---|
| all three | 0.2168 | 1.9512 | 0.7281 | −0.3551 | 2.5 / 10 | 0.0110 |

`d_max` is above the base: the absolute asymptote is 0.217 + 1.951 = 2.168,
against a drawn top of 2.151. Residuals are against the 400 points in `curves/`.

### Table 2 — the other measurables

| quantity | value | source |
|---|---|---|
| sensitivity peak | 570 nm, 360–645 | page 11, D = 0.3 curve |
| MTF | σ 2.79 µm, rms 2.0 % | page 11, 5–60 cycles/mm |
| grain | 0.6079 grains/µm² | page 8, rms granularity 10 |
| dyes | none | a silver image |
| mask | none | a silver image |

### Figures

- `figures/01-curves.png` — the fit and the 400 digitised points.
- `figures/02-residuals.png` — point minus fit: a one-pixel quantisation
  sawtooth through the whole curve, and two spikes down to −0.053 and −0.043 at
  −2.1, where the panel's three line styles merge into one stroke and the reader
  shares a single reading between them. Removing those fourteen points takes the
  rms from 0.0110 to 0.0099, so the merge is 10 per cent of the residual in
  3 per cent of the points.
- `figures/03-spectra.png` — the panchromatic sensitivity, with the dye rows
  absent because a silver film has none.

## 5. What is measured and what is decided

Measured: the curve at the reference development, the base, the MTF, the
granularity, the sensitivity, and the exposure axis itself.

Decided:

1. **The 0.02 window.** The shoulder is unmeasured; §3.2 shows what a larger one
   would buy.
2. **Eight minutes as the reference.** The panel's own middle curve and the time
   the sheet's other data are written around.
3. **The D = 0.3 sensitivity curve.** The sheet prints two; the model has one.
4. **The zero beyond 645 nm.** The sheet's own end, held at nothing rather than
   at its last value.
5. **One record for three channels.** The format asks for three; a silver image
   has one.

## 6. Uncertainty and limits

The reading is a raster at 300 dpi: 400 points spaced about 0.010 decades, with
a y quantisation of one pixel ≈ 0.002 of a density. The residual, 0.0110, is five
pixels — larger than the colour films' 0.004 because the panel draws three line
styles into one frame and the reader has to separate them, and the single-rate
fit that the first version used reached 0.0107 on the same points with a very
different shape. That the two models agree to 0.0003 of residual while putting
the asymptote 0.47 apart is the honest measure of how little this curve says
about its shoulder.

The anchor's 0.18-stop speed error is within the family's spread (TRI-X 0.10,
Kodak colour 0.60–0.80) and is not corrected for, because the anchor is the
reference exposure and not the speed point.

## 7. Availability and reproduction

`tmax-400.kalofilm` carries the header, the tables and a SHA-256;
`kalo render --film-file` loads it. The figures are regenerated from `curves/`
and the file with

```bash
python3 ../tools/kalofilm.py --check tmax-400.kalofilm        # magic, digest, sizes
python3 ../tools/kalofilm.py --csv /tmp/film tmax-400.kalofilm
```

The points in `curves/` are in the model's exposure frame — the sheet's absolute
axis shifted by +0.6953 — and carry absolute diffuse-visual density, base
included; `curves/README.md` states the shift so the fit can be recomputed from
the sheet's own axis.

No image of the data sheet is reproduced in this directory.

## References

1. Eastman Kodak Company, *KODAK PROFESSIONAL T-MAX 400 Film Technical Data*,
   publication F-4043, October 2007, pages 8, 9 and 11.
2. Kallotype, *The `.kalofilm` format, version 1*, `../FORMAT.md`.
3. Kallotype, `films/trix-400/REPORT.md` — the first silver film and the first
   absolute-axis speed check.
