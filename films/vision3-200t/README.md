# KODAK VISION3 200T

The tungsten cinema stock: same five rasters as the daylight films and two traps
of its own — a process note printed inside the dye plot, and a cyan sensitivity
curve that starts at a dip rather than a tail.

- **The report:** [REPORT.md](REPORT.md) — the note inside the plot, the clamped
  cyan tail, the shared dye set, and the granularity chart that merges into two
  curves instead of three.
- **The film:** `vision3-200t.kalofilm` (5,651 bytes) — load it with
  `kalo render --film-file`.
- **The points:** `curves/` — 563 points per layer.
- **The figures:** `figures/` — `01-curves`, `02-residuals`, `03-spectra`, drawn
  from `curves/` and the file's own tables.

Headline numbers: the curves climb to 1.65 (red), 1.96 (green) and 1.87 (blue)
above their bases; base 0.184, 0.583 and 0.853; γ 0.477, 0.559 and 0.536 per
decade; residuals 0.0037, 0.0040 and 0.0037; layer sensitivities peak at 645,
550 and 440 nm; MTF σ 4.25, 3.49 and 3.14 µm. At mid grey the negative sits 0.61
to 0.70 of a density above base. Grain, dyes and the mask are borrowed from the
500T digitisation, and the file says why.

Data and prose: CC BY 4.0. See [../LICENSE](../LICENSE) and
[../NOTICE.md](../NOTICE.md).
