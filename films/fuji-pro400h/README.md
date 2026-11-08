# FUJICOLOR PRO 400H

`fuji-pro400h.kalofilm` — 5,581 bytes.

A daylight colour negative, C-41, ISO 400, with an orange mask. Its interest is
the **fourth layer**: besides the blue-, green- and red-sensitive layers it
carries a cyan-sensitive one (ca. 470–540 nm) that forms no dye of its own.

| | |
|---|---|
| process | negative (C-41), reference 6.5 min at 20 °C |
| contrast | γ 0.96 / 0.86 / 0.80 (C/M/Y) |
| density range | d_max 1.79 / 1.72 / 1.66 above base; base 0.134 / 0.636 / 0.902 |
| grain | 5.05 (cyan) and 2.02 (magenta) grains/µm², measured from real film |
| blur | σ 3.79 µm, one MTF curve for the film |

## The fourth layer

Panel 19 of the data sheet draws four sensitivities; panel 18 draws one curve
per dye. The cyan curve is therefore the *sum* of whatever feeds the cyan dye,
and the share each contributor holds is not published. Fitting a two-emulsion
split to that sum drives the share to the edge of its range and fits no better
than the digitisation noise explains — there is no second density to find.

The literature says why. Fuji's 1989 paper on REALA, the film that introduced
this fourth layer, describes it as releasing **development inhibitors** in
proportion to exposure, pulling back the red-sensitive layer to approximate the
negative lobe of the colour matching functions. A layer like that forms no
density, and on a neutral wedge — the exposure every characteristic curve is
made with — it is exposed uniformly, so its inhibition is absorbed into the
curve that was measured.

This file therefore carries the fourth layer's **sensitivity**, under
`cl_sensitivity`, for a renderer that models it as an inhibitor source. It
contributes nothing to any channel's density, and the cyan channel carries the
summed curve.

## How the numbers were read

Four panels on one page. The digitisation of each is a documented process with a
failure mode, and the failure modes are the reason to trust the numbers.

**Panel 18, the characteristic curves** — three curves, 294 points each, over
−3.58 to +0.42 decades. The plot is a raster, so the curves were tracked column
by column after three things were removed: the frame and gridlines (a 2-pixel
dark run is indistinguishable from a curve), the panel's own labels (removed by
component size, so a curve passing behind lettering survives), and the
axis-crossing ticks. The fit:

| layer | points | rms | max residual | `t` |
|---|---|---|---|---|
| red (cyan-forming) | 294 | 0.0224 | 0.061 | 2.0 |
| green (magenta-forming) | 294 | 0.0241 | 0.058 | 2.0 |
| blue (yellow-forming) | 294 | 0.0246 | 0.062 | 2.0 |

`t = 2.0` is softer than the 4.0 the model defaults to, and it was chosen by
residual: at `t = 4.0` the same data fits at rms 0.030, at 2.0 at 0.022. A film's
corners are not a paper's.

**Panel 19, four spectral sensitivities** — and the reason this film matters.
The panel draws three solid curves and a **dashed** cyan-sensitive one. The
curves cross twice, one is dashed, and a follower that reaches a crossing has to
choose a branch; four attempts at choosing all chose wrong. They were therefore
read by **perpendicular distance to a coarse guide curve**, iterated four times,
which never has to decide — every ink pixel goes to whichever curve it is nearest
to. The perpendicular part is not fussiness: on a band's steep flank a 2-pixel
error in wavelength is a 60-pixel error in height, which is why the
vertical-distance version kept the plateaus and lost both flanks. Peaks: 470,
555, 610 nm solid, and 520 nm for the dashed layer at 0.08 of the blue layer's
height.

**Panel 20, the MTF** — one curve, both axes logarithmic. `ln(MTF)` against `f²`
is a straight line whose slope is `−2π²σ²`, so the fit is exact rather than a
descent. Over 5–60 cycles/mm: **σ 3.79 µm, rms 4.2 % of response**, 46 % against
the sheet's 47 % at 50 cycles/mm. One thing had to be done first: the drawing's
low-frequency plateau sits at 111 %, and a modulation transfer function is 1 at
zero frequency by definition, so the curve is normalised to its own plateau
before the fit. Fitting the drawing as-is would produce something that is not a
transfer function.

**Panel 21, spectral dye density** — two lines: the minimum density and the
density of a mid-scale neutral. The first is the film's **orange mask**, and it
is measured here rather than borrowed. It cross-checks against the status base
densities where the status filters sit:

| wavelength | mask, this digitisation | status base density | reading |
|---|---|---|---|
| ~620 nm | 0.19 | 0.134 | red filter reads a band, not a point |
| ~540 nm | 0.70 | 0.636 | as above |
| ~450 nm | ~1.05 | 0.902 | as above |

The agreement is what says the digitisation is the film and not an artefact of
the axes — and the residual difference is the status filters' bandwidth, which
is the expected direction of the disagreement.

**The grain does not come from the sheet.** It has no granularity figure. It was
measured from **real film** — frames shot on Fuji NPH 400, this emulsion before
the rename, from the BlueNeg archive, scanned at 3.5 µm per pixel and 16 bits
linear. The measurement is the sheet's own aperture, 48 µm:

| layer | patches | grains/µm² | quartiles |
|---|---|---|---|
| cyan | 24 | 5.05 | 3.9–6.8 |
| magenta | 24 | 2.02 | 1.6–2.2 |
| yellow | — | 5.42 (placeholder) | not measurable |

Density noise comes straight from the raw values, which are linear in
transmitted light, so relative noise over `ln 10` is density noise and no scanner
calibration is needed. The scanner's own contribution is separated **by colour**,
not by a number from another scanner: a scan's noise is common to its three
channels while developed grains are not, so the covariance between two channels'
noise is the scanner's variance. The yellow record could not be measured on the
frames in hand — its patches sit where the scan's noise floor dominates and the
inversion returns 15 to 44 grains/µm², which is the floor talking. It keeps the
compiled placeholder, and the file says which number is which.

## The fourth layer: a negative result worth printing

The obvious reading of panels 18 and 19 together is that the cyan dye is fed by
two emulsions, and ADR 0017 built the model for it. The split does not fit. With
the speed difference taken from the two sensitivities, the fit
`D(x) = f·C(x) + (1−f)·C(x−Δ)` drives the share `f` to the edge of its range and
is flat there: the measured cyan curve has no second density to find.

The literature says why. Fuji's 1989 paper on REALA, the film that introduced
this fourth layer, describes it as sensitive to cyan light and **releasing
development inhibitors** against the red-sensitive layer — not as a second
cyan-forming emulsion. On a neutral wedge, the exposure every characteristic
curve is made with, such a layer is exposed uniformly, so its inhibition is
uniform and it is already inside the measured curve.

The consequence is in the file: the fourth layer's sensitivity is carried as
`cl_sensitivity` for a renderer that models it as an inhibitor source, and it
contributes nothing to any channel's density. Its strength and diffusion length
are placeholders in the model, and no data sheet measures them.

## Figures

`figures/curves.png` draws the three fitted curves as lines and the 294 points
per layer as dots, shifted to **density above base** so the two share an axis —
without the shift the points float above their own fit by the orange mask.
`figures/spectra.png` draws what the file carries: three layer sensitivities, the
borrowed dye shapes, the measured mask and the fourth layer's sensitivity.

No image of the data sheet is reproduced here. The figures are plots of the
digitised numbers, and `tools/plot.py` regenerates them from `curves/` and the
`.kalofilm` file alone.

## What is borrowed, and what is a placeholder

- **Dye shapes are borrowed** from the VISION3 500T digitisation. This sheet
  prints one mid-scale neutral rather than three dyes, and one curve cannot be
  inverted into three spectra. The file says so in `[measured]`.
- **The yellow layer's grain** is the compiled placeholder of 5.42. On the
  frames in hand its record sits where the scan's noise floor dominates and the
  inversion returns nonsense; the two layers that could be measured are
  reported, and this one is labelled.
- **The fourth layer's inhibitor strength and diffusion length** are
  placeholders (12 % and 20 µm). No data sheet measures them. They need a
  controlled target — a step or a sinusoid shot on film through two filters —
  and nothing in the archive is that target.

## References

1. FUJIFILM, *FUJICOLOR PRO 400H Professional* data sheet **AF3-176E**, page 8.
2. Y. Takahashi et al., *Color reproduction of Fujicolor REALA*, J. Soc.
   Photogr. Sci. Technol. Japan **52**(1), 1989 —
   <https://www.jstage.jst.go.jp/article/photogrst1964/52/1/52_1_41/_article/-char/en>
   (the fourth layer's mechanism).
3. Liu et al., *BlueNeg: A 35 mm Negative Film Dataset* (ICCV 2025),
   <https://huggingface.co/datasets/ttgroup/blueneg-release> — the real film the
   grain was measured from; licence CC-BY derivative.

## Licence

Data and prose: CC BY 4.0 — see [../LICENSE](../LICENSE) and
[../NOTICE.md](../NOTICE.md).
