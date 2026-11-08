# Digitised characteristic curves

`red.csv`, `green.csv`, `blue.csv` — the three curves of the
characteristic-curve panel of E-4000 page 3, read from the PDF's own polylines.

- **Columns:** `log_e,density`. Density is total: for a reversal the film's
  density *is* the image, so no base is subtracted. `log_e` is the model's
  exposure scale, shifted from the sheet's absolute lux-seconds by −0.1001
  decade so that 18 % grey is a density of `d_max + 0.745`. The shift is solved
  by `anchor_vector_reversal.py`, not chosen, and it moves with `d_max` — the
  one number on this sheet that is an extrapolation.
- **All three curves are complete.** Unlike PROVIA's plates, nothing here is
  overprinted: each layer is fitted on its own ink, which is why the three
  residuals (0.012, 0.014, 0.015) differ by their own shape and not by how much
  of each survived.
- **The fit needs two corner rates** — 5 at the toe, 2.5 at the shoulder — and
  the residual is two lobes of ±0.03 at that shape against ±0.06 at one. The
  report's section 5 says how that was established, including the two wrong
  readings it took.
- **Why the points are here:** so the fit in `../REPORT.md` can be recomputed
  rather than believed.
