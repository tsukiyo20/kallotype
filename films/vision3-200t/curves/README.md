# Digitised characteristic curves

`red.csv`, `green.csv`, `blue.csv` — the three curves of H-1-5213's sensitometric
panel, read from its 8-bit raster, 563 points each.

- **Columns:** `log_e,density`. Density is the plate's absolute Status M density,
  base included; the model's curve is the dye *above* base, and the file's
  `[base] density` is what separates the two. The log exposure is the sheet's
  *camera-stops* axis converted to decades.
- **Which curve is which.** The panel labels its curves B, G and R: the top curve
  is blue, the middle green, the bottom red.
- **The ends are the plate's.** The ink runs from −3.47 to +1.31 on the sheet's
  axis; nothing is extrapolated in these files. The curve has no shoulder — it is
  cut while still climbing — so the fitted `d_max` is an extrapolation and
  `../REPORT.md` says so.
- **Why the points are here:** so the fit can be recomputed rather than believed.
