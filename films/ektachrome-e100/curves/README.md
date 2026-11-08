# Digitised characteristic curves

`red.csv`, `green.csv`, `blue.csv` — the three curves of the
characteristic-curve panel of E-4000 page 3, read from the PDF's own polylines.

- **Columns:** `log_e,density`. Density is total: for a reversal the film's
  density *is* the image, so no base is subtracted. `log_e` is the model's
  exposure scale, shifted from the sheet's absolute lux-seconds by +0.2145
  decade so that 18 % grey is a density of `d_max + 0.745`. The shift is solved
  by `anchor_vector_reversal.py`, not chosen.
- **All three curves are complete.** Unlike PROVIA's plates, nothing here is
  overprinted: each layer is fitted on its own ink, which is why the three
  residuals (0.037, 0.042, 0.045) differ by their own shape and not by how much
  of each survived.
- **The residual has structure and the report says so:** it is two lobes of
  ±0.06, not noise, and the model's single transition cannot remove them.
- **Why the points are here:** so the fit in `../REPORT.md` can be recomputed
  rather than believed.
