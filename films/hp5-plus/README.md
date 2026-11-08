# ILFORD HP5 PLUS

The first film in this series whose manufacturer's sheet cannot fill the file:
one characteristic curve, and no spectral sensitivity, MTF or granularity
anywhere in it.

- **The report:** [REPORT.md](REPORT.md) — reading a curve from a 488-pixel
  raster, anchoring a film whose axis is relative, and what a data format does
  when four of its five fields are absent.
- **The film:** `hp5-plus.kalofilm` (5,552 bytes) — load it with
  `kalo render --film-file`.
- **The points:** `curves/` — 164 points, the same curve in all three files.
- **The figures:** `figures/` — `01-curves`, `02-residuals`, `03-spectra`.

Headline numbers: the curve climbs to 1.98 above a base of 0.177; γ 0.650 per
decade; residual 0.0065 — about a pixel and a half of the raster; at 18 per cent
grey the density is 0.832 above base, where the anchor is the ISO definition of
speed rather than a printed axis.

The layer response is **flat** because the sheet publishes no sensitivity chart,
the blur is **absent** because it publishes no MTF, and the grain is the
**compiled placeholder** averaged across the channels. The file says all three
things in its `[measured]` table.

Data and prose: CC BY 4.0. See [../LICENSE](../LICENSE) and
[../NOTICE.md](../NOTICE.md).
