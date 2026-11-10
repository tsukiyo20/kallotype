# Digitised characteristic curves

`red.csv`, `green.csv`, `blue.csv` — the three curves of the characteristic-curve
panel of AF3-960E, read from one stencil.

- **Columns:** `log_e,density`. Density is the plate's absolute density; the
  model's curve is the same quantity for a reversal (an unexposed slide is
  dense), so no offset is applied when plotting. The log exposure is anchored
  so that 18 per cent grey is a density of `d_max + 0.745`; the shift is
  −0.1364 decade.
- **The three curves overlap without crossing.** Green is the top curve, blue
  the middle, red the bottom, at every exposure; the reader uses that order
  above density 2.4. Below it the sheet merges the three into one bundle and
  the layers share one centreline, which is why the lower half of the three
  files is identical.
- **The gap at the knee.** The runs are one tall bundle for about 0.2 decade
  before the merged reader starts; that stretch is not sampled and the fit
  interpolates it. `../REPORT.md` §3.1 says what was tried instead.
- **Why the points are here:** so the fit in `../README.md` can be recomputed
  rather than believed.
