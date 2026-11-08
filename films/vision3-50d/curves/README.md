# Digitised characteristic curves

`red.csv`, `green.csv`, `blue.csv` — the three curves of H-1-5203's sensitometric
panel, read from its 8-bit raster.

- **Columns:** `log_e,density`. Density is the plate's absolute Status M density,
  base included; the model's curve is the dye *above* base, and the file's
  `[base] density` is what separates the two. The log exposure is the sheet's
  *camera-stops* axis converted to decades; the sheet's separate log-exposure
  axis disagrees with it by about 0.15 decade across the frame, which is what a
  rounded illustration does.
- **The frame.** The sheet prints camera stops and no reference exposure, so
  the points are shifted by **+0.5141 decade** to put the printing aim — green at
  0.70 of a density above base at mid grey — on the model's log10(0.18).
- **Which curve is which.** The panel labels its curves B, G and R at their
  high-exposure ends; the top curve is blue, the middle green, the bottom red.
- **The red curve is dotted.** The sheet draws red as a dotted stroke while green
  and blue are solid. The tracker reads a dot the same way it reads a line — a
  three-pixel run in a column — so red yields 349 samples instead of 538, and its
  residual (0.0065) carries that jitter rather than the fit's error.
- **The ends are the plate's.** The ink runs from −3.35 to +1.41 on the sheet's
  axis; nothing is extrapolated in these files. The curve has no shoulder — it is
  cut at +8 stops while still climbing — so the fitted `d_max` is an
  extrapolation and `../REPORT.md` says so.
- **Why the points are here:** so the fit can be recomputed rather than believed.
