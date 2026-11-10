# Digitised characteristic curves

`red.csv`, `green.csv`, `blue.csv` — the three curves of E-4051's characteristic
panel, read from the page's vector paths, 128 points each.

- **Columns:** `log_e,density`. Density is the plate's absolute Status M density,
  base included; the model's curve is the dye *above* base, and the file's
  `[base] density` is what separates the two. The log exposure is the sheet's own
  axis shifted by **+0.3063 decade** so that the printed `Log H Ref: -1.051` —
  the exposure an 18 per cent grey card receives at the film's EI 160 rating —
  lands on the model's log10(0.18). The shift is the sheet's number, not a fit.
- **Which curve is which.** The panel labels its curves B, G and R at the
  low-exposure end: the top curve is blue (minimum density 0.842), the middle
  green (0.628), the bottom red (0.212). Those three minima are the base
  densities the file carries.
- **The paths are cubic.** Each of the three curves is twenty cubic Bézier
  segments with no straight pieces; the reader evaluates each cubic at twelve
  points. On this sheet the knots are 0.2 decade apart, so the endpoints-only
  reading this project used before was in error by less than 0.006 of a density.
- **The ends are the plate's.** The curves are drawn from −3.04 to +0.96 on the
  sheet's own axis, which is −2.73 to +1.27 in the model's frame; nothing is
  extrapolated in these files.
- **Why the points are here:** so the fit in `../README.md` can be recomputed
  rather than believed.
