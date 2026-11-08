# FUJICHROME PROVIA 100F (RDP III)

`provia-100f.kalofilm` — 5,444 bytes.

A daylight colour reversal film, E-6, ISO 100. The film *is* the picture: there
is no negative and no paper between the exposure and the eye, so a slide's
density is absolute — about 3.3 in the darkest part of an unexposed frame,
0.08 in the clear.

| | |
|---|---|
| process | reversal (E-6), reference 6.5 min at 20 °C |
| contrast | γ 2.08 on all three layers |
| density range | d_min 3.31 / 3.35 / 3.46 → d_max 0.079 / 0.114 / 0.229 (C/M/Y) |
| grain | 6.17 grains/µm², from the sheet's diffuse rms granularity of 8 |
| blur | σ 4.68 µm, one MTF curve for the film, carried by all three layers |

## How the numbers were read

All four panels are on one page, and each needed a different reading.

**The characteristic curves** are three separate ink plates printed over one
another. The red plate is complete. The green and blue plates overlap it for
most of their length, so instead of tracking three curves through a region where
two inks are the same colour, each of the other two carries the red layer's
shape with its own measured offset. The residuals against the digitised points
are what that costs:

| layer | points | rms | why |
|---|---|---|---|
| red | 768 | 0.0254 | its own plate, no overlap |
| green | 183 | 0.0090 | one offset from red, and the plates barely overlap |
| blue | 320 | 0.0510 | two overprinted inks; the worst reading on the page |

The columns, the file and the figure all say which layer is which and how the
fit was done, so a reader can recompute the residual rather than take the number
on trust. `curves/` holds the points; `figures/curves.png` draws them under the
fitted curve.

**The layer sensitivities** are the only panel in this project's archive that is
**vector artwork** rather than a raster. That means they were read from their
stroked Bézier paths, not tracked pixel by pixel, at 5 nm resolution: the
blue-sensitive layer peaks at 455 nm and 1.09 decade, the green at 543 and 0.82,
the red at 642 and 1.00. Outside each drawn path the response is held at a floor
one decade below its minimum — a path stops where the layer stops responding,
and a slope continued for fifty nanometres would invent a response the sheet
does not show.

**The dyes** are three plates too, but each is a single ink, so there is no
overlap problem: yellow absorbs at 443 nm, magenta at 543, cyan at 658 with its
red edge out at 700 nm. They are peak-normalised, which is the convention the
model's print stage expects.

**The MTF** is one curve for the film, both axes logarithmic. A Gaussian point
spread of σ has a transfer function `exp(−2π²σ²f²)`, so `ln(MTF)` is a straight
line against `f²` and the fit is an exact solve with one free parameter. Over
5–60 cycles/mm it gives **σ 4.68 µm, rms 2.8 % of response**. The panel publishes
one curve, so all three layers carry that blur; splitting it would be invention.

**The grain** is not digitised from a curve — the sheet prints one number, a
diffuse rms granularity of 8 at a 48 µm aperture, and the grain density is
derived from it. At a mean density `D` a fraction `c = 1 − 10^(−D)` of the layer
is covered, an aperture of area `A` holds `n·A·c` developed grains, and the
density fluctuates by

    sigma_D = slope / (ln 10 · sqrt(n · A · c))

so with the sheet's number, the curve's slope at that density and the coverage,
`n = 6.17 grains/µm²`. That is an **assumption** — that grains are Poisson —
rather than a measurement of a granularity curve, and it is the weakest number
in this file.

## The fit

The characteristic curve is a four-parameter model:

    D(x) = d_min + (γ/t) · (softplus(t(x − toe)) − softplus(t(x − shoulder)))

with `d_min`, `d_max` (= d_min + γ·(shoulder − toe)), `γ`, the mid-point
`log_e0` and the corner sharpness `t`. For a fixed `t` and a pair of corners the
model is **linear in d_min and the amplitude**, so the fit is an exact
least-squares solve over a grid of corners rather than a descent that might stop
in a local minimum. `t = 4.0` for this film, and the choice was made by
residual: the wider grid with `t` free gained nothing over the reported rms.

## Figures

`figures/curves.png` draws the three fitted curves as lines and the digitised
points as dots, both in **density above base** — a reversal's `d_min` is the
density of the unexposed slide, so the file's curve and the sheet's points match
without an offset. `figures/spectra.png` draws what the `.kalofilm` file
actually carries: three layer sensitivities and three dyes.

No image of the data sheet is reproduced anywhere in this directory. The figures
are plots of the digitised numbers, and `tools/plot.py` regenerates them from
`curves/` and the `.kalofilm` file alone.

## What is not measured

- **Grain** is not digitised from a curve. The sheet prints one number, a
  diffuse rms granularity of 8 at a 48 µm aperture, and the grain density is
  derived from it through counting statistics: at a mean density `D` a fraction
  `1 − 10^(−D)` of the layer is covered, an aperture holds `n·A·c` grains, and
  the density fluctuates by `slope / (ln 10 · √(n·A·c))`. That inversion is an
  assumption — that the grains are Poisson — not a measurement of the curve.
- **The MTF** is one curve for the film, so the three layers share one blur.
  The sheet draws it that way; splitting it would be invention.
- **Nothing about halation.** Halation is a property of the film plus the
  camera plus the light, and no data sheet measures it.

## References

1. FUJIFILM, *FUJICHROME PROVIA 100F Professional* data sheet **AF3-036E**,
   page 6 (characteristic curves, spectral sensitivity, MTF, dye density).
2. The layer tables use the standard 10 nm CIE colour matching functions and a
   5 nm model grid; both are constants of the model, not of this film.

## Licence

Data and prose: CC BY 4.0 — see [../LICENSE](../LICENSE) and
[../NOTICE.md](../NOTICE.md). Cite the data sheet above and the file.
