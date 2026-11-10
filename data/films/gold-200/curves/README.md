# Digitised characteristic curves

`red.csv`, `green.csv`, `blue.csv` — the three curves of E-7022's characteristic
panel, read from the page's vector paths, 128 points each.

- **Columns:** `log_e,density`. Density is the plate's absolute Status M density,
  base included; the model's curve is the dye *above* base, and the file's
  `[base] density` is what separates the two. The log exposure is the sheet's own
  axis shifted by **+0.3953 decade** so that the printed `Log H Ref: -1.14` — the
  exposure an 18 per cent grey card receives at the film's EI 200 rating — lands
  on the model's log10(0.18).
- **Which curve is which.** The panel labels its curves B, G and R at the
  low-exposure end: the top curve is blue (minimum density 0.984), the middle
  green (0.644), the bottom red (0.255). Those three minima are the base
  densities the file carries.
- **Cubics sampled, not chorded.** Each path carries four to six cubic Bézier
  segments; the reader evaluates each at twelve points instead of taking its end
  point. On this sheet the old reading put the red and green curves up to 0.05 of
  a density away from their own artwork — §3.2 of `../REPORT.md`.
- **The ends are the plate's.** The curves are drawn from −3.00 to +0.87 on the
  sheet's own axis, which is −2.60 to +1.27 in the model's frame; nothing is
  extrapolated in these files.
- **Why the points are here:** so the fit in `../README.md` can be recomputed
  rather than believed.
