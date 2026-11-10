# Digitised characteristic curve

`red.csv`, `green.csv`, `blue.csv` — the same curve three times: the **6-minute**
curve of the D-76 panel on printed page 12, read from the page's vector path,
128 points.

A silver film has one record. The model's tables have three channels, so the
file carries this curve in all three slots and marks the stock `monochrome`; the
renderer then exposes it through its spectrum on one record rather than three.

- **Columns:** `log_e,density`. Density is the plate's absolute diffuse visual
  density, base included; the model's curve is the density *above* base, and the
  file's `[base] density` of 0.2618 is what separates them. The log exposure is
  the sheet's own axis shifted by **+0.6953 decade** so that the reference
  exposure of an 18 per cent grey card at ISO 400 (log H = −1.44) lands on the
  model's log10(0.18).
- **Which curve.** Printed page 12 draws 400TX in D-76, large tank, 20 °C,
  1-minute agitation at 6, 8, 10 and 12 minutes. This is the 6-minute one — the
  shortest, and the nearest drawn time to the 6¾ minutes the sheet's own
  development table recommends.
- **The ends are the plate's.** The curve is drawn from log H −3.45 to +0.36 on
  the sheet's axis; nothing is extrapolated in these files.
- **Why the points are here:** so the fit in `../README.md` can be recomputed
  rather than believed.
