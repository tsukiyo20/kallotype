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

## Where the numbers came from

FUJIFILM product information bulletin **AF3-176E**, page 8, four panels:

| panel | what | how it was read |
|---|---|---|
| 18 | characteristic curves | 294 points each, rms 0.022 against the fitted curve |
| 19 | four spectral sensitivities | four curves, the fourth dashed; digitised against the panel's own gridlines and its 1.0-decade bar |
| 20 | MTF | one curve, log–log; σ 3.79 µm, rms 4.2 % of response over 5–60 cycles/mm, 46 % against the sheet's 47 % at 50 cycles/mm |
| 21 | dye density | the minimum-density line is the film's **mask**, and it is measured here rather than borrowed |

The mask cross-checks against the status base densities where the status
filters sit — 0.19 at 620 nm against 0.134, 0.70 at 540 against 0.636, ~1.05 at
450 against 0.902 — which is the check that says the digitisation is the film
and not an artefact of the axes.

The grain does not come from the sheet; it has no granularity figure. It was
measured from **real film**: frames shot on Fuji NPH 400 — this emulsion before
the rename — from the BlueNeg archive, scanned at 3.5 µm per pixel, 16 bits
linear. The measurement is the sheet's own aperture, 48 µm: density noise
taken straight from the raw values (they are linear in transmitted light, so
relative noise over ln 10 is density noise), with the scanner's contribution
separated by colour, because a scan's noise is common to its three channels
while developed grains are not.

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
