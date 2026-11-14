# FUJICOLOR PRO 400H

A C-41 colour negative with a cyan-sensitive fourth layer, digitised from its
data sheet and its grain measured from real film. Version 2 re-derives the curves
with the series' two-rate rising fit and re-anchors them on the printing aim —
its data sheet's absolute exposure axis contradicts its own ISO rating, and the
report shows the three candidate shifts.

- **The report:** [REPORT.md](REPORT.md) — method, fits, residuals, uncertainty,
  and the negative result about the fourth layer.
- **The film:** `fuji-pro400h.kalofilm` (7,548 bytes) — load it with
  `kalo render --film-file`.
- **The points:** `curves/` — 294 digitised points per layer, so the fit can be
  recomputed rather than believed.
- **The figures:** [01-curves](figures/01-curves.png), [02-residuals](figures/02-residuals.png), [03-spectra](figures/03-spectra.png),
  drawn from `curves/` and the file's tables.

Headline numbers: curve rms 0.0038–0.0045 at 294 points/layer; four sensitivities
peaking at 470, 555, 610 and 520 nm; a measured orange mask; σ 3.79 µm from the
MTF; grain 5.05 and 2.02 grains/µm² for the cyan and magenta layers, measured
from NPH 400 scans.

Data and prose: CC BY-SA 4.0. See [../LICENSE](../LICENSE) and
[../NOTICE.md](../NOTICE.md).
