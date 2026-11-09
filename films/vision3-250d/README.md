# KODAK VISION3 250D

The daylight baseline of the family: five raster charts on two pages, the sharpest
of the three VISION3 films, and the sheet whose digitisation taught the readers
what a raster sheet with no shoulder and a merged MTF curve does to a tracker.

- **The report:** [REPORT.md](REPORT.md) — the shoulder that is not drawn, the MTF
  that merges with its own 100 % rule, the granularity chart the tracker cannot
  read, and the dye set the model shares with the 500T.
- **The film:** `vision3-250d.kalofilm` (5,727 bytes) — load it with
  `kalo render --film-file`.
- **The points:** `curves/` — 538 points per layer.
- **The figures:** [01-curves](figures/01-curves.png), [02-residuals](figures/02-residuals.png), [03-spectra](figures/03-spectra.png), drawn
  from `curves/` and the file's own tables.

Headline numbers: the curves climb to 1.67 (red), 1.99 (green) and 1.90 (blue)
above their bases; base 0.175, 0.574 and 0.844; γ 0.475, 0.557 and 0.537 per
decade; residuals 0.0050, 0.0052 and 0.0055; layer sensitivities peak at 655,
550 and 465 nm; MTF σ 4.25, 3.34 and 3.09 µm. At mid grey the negative sits 0.61
to 0.70 of a density above base. Grain, dyes and the mask are borrowed from the
500T digitisation, and the file says why.

Data and prose: CC BY-SA 4.0. See [../LICENSE](../LICENSE) and
[../NOTICE.md](../NOTICE.md).
