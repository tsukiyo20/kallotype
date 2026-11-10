# Digitised characteristic curves

`red.csv`, `green.csv`, `blue.csv` — the three curves of H-1-5207's sensitometric
panel, read from its 8-bit raster, 538 points each.

- **Columns:** `log_e,density`. Density is the plate's absolute Status M density,
  base included; the model's curve is the dye *above* base, and the file's
  `[base] density` is what separates the two. The log exposure is the sheet's
  *camera-stops* axis converted to decades; the sheet also prints a log-exposure
  axis that disagrees with it by about 0.15 decade across the frame.
- **The frame.** The sheet prints camera stops and no reference exposure, so
  the points are shifted by **+0.5097 decade** to put the printing aim — green at
  0.70 of a density above base at mid grey — on the model's log10(0.18).
- **Which curve is which.** The panel labels its curves B, G and R: the top curve
  is blue, the middle green, the bottom red.
- **The ends are the plate's.** The ink runs from −3.43 to +1.35 on the sheet's
  axis; nothing is extrapolated in these files. The curve has no shoulder — the
  sheet cuts it at +8 stops while it is still climbing — so the fitted `d_max` is
  an extrapolation and `../REPORT.md` says so.
- **Why the points are here:** so the fit can be recomputed rather than believed.
