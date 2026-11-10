# Digitised characteristic curve

`red.csv`, `green.csv`, `blue.csv` — the same 400 points in each, because a
silver image is one record and the format asks for three channels.

- **Columns:** `log_e,density`. Density is the plate's absolute diffuse-visual
  density, base included; the model's curve is the silver *above* base, and the
  file's `[base] density` is what separates the two. The log exposure is the
  sheet's own axis — printed absolute, `LOG EXPOSURE (lux-seconds)`, −4.0 to
  +1.0 — shifted by **+0.6953 decade** so that the exposure an 18 per cent grey
  card receives at ISO 400 (−1.4398 on the printed axis) lands on the model's
  log10(0.18). The shift is a measurement, not a convention: shifted, the curve
  reaches D_min + 0.10 within 0.18 of a stop of the rating, which is the same
  ISO check TRI-X's absolute-axis sheet closes to 0.10.
- **The curve read.** Panel 9 of F-4043, D-76 small tank at 20 °C, the
  **eight-minute** curve. The panel draws 6, 8 and 11 minutes in three line
  styles that converge into one stroke at the toe; the reader separates them by
  connected-component size and shares one reading where the reproduction has
  merged them.
- **The ends are the plate's.** The ink runs from −3.47 to +0.34 on the printed
  axis, which is −2.78 to +1.04 in the model's frame. Nothing is extrapolated in
  these files; the curve's shoulder is outside the frame, and the fit's `d_max`
  is bounded by the highest drawn density rather than drawn from a continuation.
- **Why the points are here:** so the fit in `../REPORT.md` can be recomputed
  rather than believed.
