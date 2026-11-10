# Digitised characteristic curves

`red.csv`, `green.csv`, `blue.csv` — the EI 800 panel of E-4040's characteristic
curves, read from the page's vector paths, 128 points each.

- **Columns:** `log_e,density`. Density is the plate's absolute Status M density,
  base included; the model's curve is the dye *above* base, and the file's
  `[base] density` is what separates the two. The log exposure is the sheet's own
  axis shifted by **+0.9953 decade** so that the printed `Log H Ref: -1.74` — the
  exposure an 18 per cent grey card receives at EI 800 — lands on the model's
  log10(0.18).
- **Which curve is which.** The panel labels its curves B, G and R at the
  high-exposure end, in the order they terminate: blue is the top curve (minimum
  density 1.011), green the middle (0.705), red the bottom (0.302).
- **The axis is stated, not read.** The panel prints its log H labels as
  −4.0, −2.0, −3.0, −1.0, 0.0, 1.0 — the second and third swapped. The tick marks
  are exact and evenly spaced, and they say where −4 and +1 are; §3.1 of
  `../REPORT.md` records how.
- **The ends are the plate's.** The curves are drawn from −2.745 to +1.255 in this
  frame; nothing is extrapolated in these files.
- **Why the points are here:** so the fit in `../README.md` can be recomputed
  rather than believed.
