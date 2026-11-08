# Digitised characteristic curves

`red.csv`, `green.csv`, `blue.csv` — the three curves of panel 18 of AF3-176E,
read at every second pixel of a 300 dpi raster and converted to
(log10 exposure, status-M density).

- **Columns:** `log_exposure,density`. Density is absolute, base and mask
  included, because that is what a densitometer reads and what the sheet draws.
  The model's curve is dye *above* base, so `figures/curves.png` subtracts the
  film's `base_density` before plotting — the offset is the orange mask.
- **The axis:** the sheet's own axis is absolute, `log H (lux-seconds)` from
  −4.0 to +1.0. These files are shifted by **+0.2633 decade** so that mid grey
  falls where the green record sits 0.70 of a density above its base; the sheet
  contradicts its own ISO rating by 1.7 stops, and `../REPORT.md` §6 shows the
  three candidate shifts and what each implies.
- **Resolution:** about 0.014 decades on the exposure axis and 0.002 in density,
  which is the pixel size of the chart divided by its axes.
- **What was removed before reading:** the frame, the gridlines and the panel's
  own text. The text was removed by connected-component size, so a curve that
  runs behind a letter survives; the gridlines were removed by position, because
  a 2-pixel dark run is indistinguishable from a curve.
- **Why the points are here:** so the fit in `../README.md` can be recomputed
  rather than believed. The rms is against these points.
