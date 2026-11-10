# Digitised characteristic curve

`red.csv`, `green.csv`, `blue.csv` — the same 367 points in each, because a
silver image is one record and the format asks for three channels.

- **Columns:** `log_e,density`. Density is the plate's absolute diffuse density,
  base included; the model's curve is the silver *above* base, and the file's
  `[base] density` is what separates the two. The log exposure is the sheet's
  relative axis shifted by **+0.1903 decade** so that the curve's D_min + 0.10
  point — the ISO 5800 speed point — lands on the model's reference exposure,
  `log10(0.18) − 1.26`. ILFORD prints no absolute exposure scale, so the speed
  point is the only anchor the page supports; HP5 PLUS is anchored the same way.
- **The curve read.** Page 6 of `d400_a.pdf`, the sheet's one characteristic
  curve: ID-11 stock, 8 minutes at 24 °C, digitised from the page's raster.
- **The ends are the plate's.** The ink runs from −3.13 to +1.17 on the sheet's
  axis, which is −2.94 to +1.36 in the model's frame. Nothing is extrapolated in
  these files; the fit's `d_max` is bounded by the highest drawn density.
- **Why the points are here:** so the fit in `../REPORT.md` can be recomputed
  rather than believed.
