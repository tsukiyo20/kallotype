# KODAK PROFESSIONAL EKTAR 100

The sharpest film in the series and the slowest Kodak negative: a stock whose
sheet prints its own exposure reference, whose dye panel gives up the orange
mask, and whose curves are drawn in three cubic segments across four decades —
the coarsest artwork in the archive, and the reason the vector reader learned to
sample a cubic instead of its endpoints.

- **The report:** [REPORT.md](REPORT.md) — the printed `Log H Ref` anchor, the
  rising fit, the Bézier correction that moved the green curve by 0.10 of a
  density, and the mask read from the sheet's D-min.
- **The film:** `ektar-100.kalofilm` (6,319 bytes) — load it with
  `kalo render --film-file`.
- **The points:** `curves/` — 128 points per layer.
- **The figures:** `figures/` — `01-curves`, `02-residuals`, `03-spectra`, drawn
  from `curves/` and the file's own tables.

Headline numbers: the curves climb to 1.74 (red), 1.79 (green) and 2.22 (blue)
above their bases; base density 0.217, 0.648 and 0.873; γ 0.576, 0.574 and 0.653
per decade; residuals 0.0087, 0.0103 and 0.0117; layer sensitivities peak at
650, 545 and 470 nm; MTF σ 4.87, 3.67 and 3.49 µm; the mask runs from 0.876 of a
density at 440 nm to 0.211 at the red end. At the sheet's printed reference
exposure — an 18 per cent grey card at EI 100 — the green record sits 0.720 above
its base, against the 0.70 a C-41 negative is balanced on. Grain is not claimed:
the sheet publishes a Print Grain Index and says it cannot be compared to rms
granularity. The dye shapes are borrowed from the VISION3 500T digitisation.

Data and prose: CC BY-SA 4.0. See [../LICENSE](../LICENSE) and
[../NOTICE.md](../NOTICE.md).
