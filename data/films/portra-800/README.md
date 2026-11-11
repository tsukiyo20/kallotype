# KODAK PROFESSIONAL PORTRA 800

The second Kodak colour negative in this series, and the first sheet it has read
that draws the same film at three exposure indices.

- **The report:** [REPORT.md](REPORT.md) — the axis the typesetter printed out of
  order and the tick marks that settle it, the anchor at EI 800, the EI 1600 and
  EI 3200 panels as a development ladder, and the mask read from the dye panel.
- **The film:** `portra-800.kalofilm` (6,379 bytes) — load it with
  `kalo render --film-file`.
- **The points:** `curves/` — 128 points per layer, at EI 800.
- **The figures:** [01-curves](figures/01-curves.png), [02-residuals](figures/02-residuals.png), [03-spectra](figures/03-spectra.png), drawn
  from `curves/` and the file's own tables.

Headline numbers: the curves climb to 1.65 (red), 1.72 (green) and 1.96 (blue)
above their minima; base density 0.302, 0.705 and 1.011; γ 0.521, 0.534 and 0.608
per decade; residuals 0.0026, 0.0035 and 0.0038; layer sensitivities peak at 410,
545 and 655 nm; MTF σ 4.75, 3.69 and 3.00 µm; the mask falls from 0.86 to 0.26 of
a density across the visible. Pushed to EI 1600 and EI 3200 on the same sheet, γ
rises to 0.63–0.73 and 0.69–0.79. Grain is not claimed — the sheet publishes a
Print Grain Index and says it cannot be compared to rms granularity. The dye
shapes are borrowed from the VISION3 500T digitisation.

Data and prose: CC BY-SA 4.0. See [../LICENSE](../LICENSE) and
[../NOTICE.md](../NOTICE.md).
