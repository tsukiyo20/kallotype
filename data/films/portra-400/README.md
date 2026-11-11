# KODAK PROFESSIONAL PORTRA 400

The second colour negative in this series and the first Kodak one: a film whose
curves climb, whose sheet prints its own exposure anchor, and whose orange mask
is a measured spectrum rather than a borrowed one.

- **The report:** [REPORT.md](REPORT.md) — why the fitter had to learn that a
  negative *rises*, the anchor the sheet prints, the two halves of the dye
  panel, and the grain number the sheet explicitly refuses to give.
- **The film:** `portra-400.kalofilm` (6,289 bytes) — load it with
  `kalo render --film-file`.
- **The points:** `curves/` — 128 points per layer.
- **The figures:** [01-curves](figures/01-curves.png), [02-residuals](figures/02-residuals.png), [03-spectra](figures/03-spectra.png), drawn
  from `curves/` and the file's own tables.

Headline numbers: the curves climb to 1.82 (red), 1.83 (green) and 2.19 (blue)
above their minima; base density 0.217, 0.651 and 0.865; γ 0.560, 0.560 and
0.648 per decade; residuals 0.0072, 0.0029 and 0.0037; layer sensitivities peak
at 410, 550 and 650 nm; MTF σ 4.45, 3.42 and 3.11 µm; the mask falls from 0.71
to 0.20 of a density across the visible. Grain is not claimed — the sheet
publishes a Print Grain Index and says it cannot be compared to rms granularity.
The dye shapes are borrowed from the VISION3 500T digitisation.

Data and prose: CC BY-SA 4.0. See [../LICENSE](../LICENSE) and
[../NOTICE.md](../NOTICE.md).
