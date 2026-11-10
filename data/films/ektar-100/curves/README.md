# Digitised characteristic curves

`red.csv`, `green.csv`, `blue.csv` — the three curves of E-4046's characteristic
panel, read from the page's vector paths, 128 points each.

- **Columns:** `log_e,density`. Density is the plate's absolute Status M density,
  base included; the model's curve is the dye *above* base, and the file's
  `[base] density` is what separates the two. The log exposure is the sheet's own
  axis shifted by **+0.0953 decade** so that the printed `Log H Ref: -0.84` — the
  exposure an 18 per cent grey card receives at the film's EI 100 rating — lands
  on the model's log10(0.18). The shift is the sheet's number, not a fit.
- **Which curve is which.** The panel labels its curves B, G and R at the
  low-exposure end: the top curve is blue (minimum density 0.873), the middle
  green (0.648), the bottom red (0.217). Those three minima are the base
  densities the file carries.
- **The paths are cubic, and sampled as cubics.** These three curves are built
  from 3 to 4 cubic Bézier segments plus up to 34 straight ones. The reader
  evaluates each cubic at twelve points rather than taking its end point; the
  difference on this sheet was up to 0.106 of a density on the green curve, and
  it is §3.1 of `../REPORT.md`.
- **The ends are the plate's.** The curves are drawn from −2.81 to +1.17 on the
  sheet's own axis, which is −2.71 to +1.27 in the model's frame; nothing is
  extrapolated in these files.
- **Why the points are here:** so the fit in `../README.md` can be recomputed
  rather than believed.
