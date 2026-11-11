# KODAK PROFESSIONAL T-MAX 400

The first film in the series that borrows nothing: its curve, its granularity,
its modulation transfer and its spectral sensitivity all come from one data
sheet, and a silver image carries no dyes and no mask to borrow.

- **The report:** [REPORT.md](REPORT.md) — the absolute exposure axis and the
  shift it needs, a shoulder that is outside the frame, the granularity number
  turned into grains, and what a monochrome film does to a three-channel model.
- **The film:** `tmax-400.kalofilm` (5,789 bytes) — load it with
  `kalo render --film-file`.
- **The points:** `curves/` — 400 points, the same record in all three files.
- **The figures:** [01-curves](figures/01-curves.png), [02-residuals](figures/02-residuals.png), [03-spectra](figures/03-spectra.png), drawn
  from `curves/` and the file's own tables.

Headline numbers: the curve climbs to 1.95 above its base; base 0.217; γ 0.728
per decade; residual 0.0110 over 400 points; MTF σ 2.79 µm — the sharpest film
in the series; grain 0.6079 grains/µm² from a diffuse rms granularity of 10; the
sensitivity peaks at 570 nm and ends at 645. At the reference exposure the
printed axis puts the film 0.18 of a stop from its ISO 400 rating, which is what
lets the axis be trusted.

Data and prose: CC BY-SA 4.0. See [../LICENSE](../LICENSE) and
[../NOTICE.md](../NOTICE.md).
