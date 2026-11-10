# Digitised characteristic curves

`red.csv`, `green.csv`, `blue.csv` — the three curves of E-4050's
characteristic panel, read from the page's vector paths, 128 points each.

- **Columns:** `log_e,density`. Density is the plate's absolute Status M density,
  base included; the model's curve is the dye *above* base, and the file's
  `[base] density` is what separates the two. The log exposure is the sheet's own
  axis shifted by **+0.6953 decade** so that the printed `Log H Ref: -1.44` — the
  exposure an 18 per cent grey card receives at the film's ISO 400 rating — lands
  on the model's log10(0.18). The shift is the sheet's number, not a fit.
- **Which curve is which.** The panel labels its curves B, G and R at the
  low-exposure end, and the order never changes: the top curve is blue (minimum
  density 0.865), the middle green (0.651), the bottom red (0.217). Those three
  minima are the base densities the file carries.
- **The ends are the plate's.** The curves are drawn from −3.39 to +0.55 on the
  sheet's axis; nothing is extrapolated in these files. The model's asymptote is
  beyond the right-hand end, which is §3.2 of `../REPORT.md`.
- **Why the points are here:** so the fit in `../README.md` can be recomputed
  rather than believed.
