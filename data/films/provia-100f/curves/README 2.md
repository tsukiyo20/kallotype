# Digitised characteristic curves

`red.csv`, `green.csv`, `blue.csv` — the three curves of the characteristic-curve
panel of AF3-036E, one per ink plate.

- **Columns:** `log_e,density`. Density is the plate's absolute density; the
  model's curve is the same quantity for a reversal (an unexposed slide is
  dense), so no offset is applied when plotting.
- **The three plates overlap.** The red plate is complete and the green and blue
  plates are read as the red layer's shape plus their own measured offsets. That
  is why the blue residual (0.051) is five times the green one (0.009): two
  overprinted inks, not a worse fit.
- **Why the points are here:** so the fit in `../README.md` can be recomputed
  rather than believed.
