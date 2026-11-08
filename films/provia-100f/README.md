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

## Where the numbers came from

FUJIFILM product information bulletin **AF3-036E**, page 6. The document's
SHA-256 is recorded in the file's `[provenance]` section, so a reader can check
that the sheet they are holding is the one this was read from.

The page is unusual in the archive: its panels are **vector artwork**, not
rasters, so the layer sensitivities were read from their stroked Bézier paths
rather than tracked pixel by pixel. Three curves, one colour each: the
blue-sensitive layer peaks at 455 nm and 1.09 decade, the green at 543 and 0.82,
the red at 642 and 1.00. Outside each drawn path the response is held at a floor
a decade below its minimum — a path stops where the layer stops responding, and
a slope continued for fifty nanometres would invent a response the sheet does
not show.

The characteristic curves are **three separate ink plates**. The red plate is
complete; the green and blue plates overlap it for most of their length, so
they carry the red layer's shape with their own measured offsets. The residuals
against the digitised points are 0.009 and 0.051 — the second is what a curve
read through two overprinted inks costs, and it is recorded here rather than
smoothed away.

The three dyes are the sheet's own, and are the reason this film was the first
to be worth releasing: most negative sheets publish one mid-scale neutral
subject rather than three dyes, and their dye shapes have to be borrowed. These
were digitised one per ink plate — yellow absorbing at 443 nm, magenta at 543,
cyan at 658 with its red edge out at 700 nm.

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
