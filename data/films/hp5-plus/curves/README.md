# Digitised characteristic curve

`red.csv`, `green.csv`, `blue.csv` — the same curve three times: ILFORD HP5 PLUS
in ILFOTEC HC (1+31) for 6½ minutes at 20 °C, read from the sheet's own raster.

- **Columns:** `log_e,density`. Density is the sheet's density, base included;
  the model's curve is the density *above* base, and the file's `[base] density`
  of 0.1771 is what separates them.
- **The exposure frame is a decision.** The sheet's axis is *relative* log
  exposure, with no lux-second scale. The curve is placed so that its crossing of
  base + 0.10 — the ISO speed point — sits at the model's log10(0.18) − 1.26,
  which is the standard's own definition of where the speed point is. The shift
  is −3.079, and unlike every other film in the series it cannot be checked
  against anything printed.
- **Where the points come from.** The curve is a 488 × 344 raster. Its grid is
  the calibration: ten vertical rules every 45.1 px with 1, 2, 3 and 4 on the
  3rd, 5th, 7th and 9th (0.5 decade per cell), seven horizontal rules every
  44.8 px with 0.0 at the bottom and 3.0 at the top (0.5 of a density per cell).
  The rules are erased a pixel wide and the curve is what is left.
- **Resolution.** One sample every 0.025 decade; the raster cannot say more. The
  fit residual is 0.0065, about a pixel and a half of ink.
- **Why the points are here:** so the fit in `../README.md` can be recomputed
  rather than believed.
