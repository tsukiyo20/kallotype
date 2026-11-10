# KODAK PROFESSIONAL PORTRA 160

The slowest film in the Kodak negative family and its best-behaved: three curves
that fit to thousandths of a density, a base that agrees with the sheet's own
mask to 0.04, and one printed number that the family's anchor formula does not
predict.

- **The report:** [REPORT.md](REPORT.md) — the `Log H Ref` that is 0.010 off the
  formula, the rising fit that lands the base on the ink's own floor, the D-min
  mask, and the anchor gap of 0.73 of a stop.
- **The film:** `portra-160.kalofilm` (6,198 bytes) — load it with
  `kalo render --film-file`.
- **The points:** `curves/` — 128 points per layer.
- **The figures:** [01-curves](figures/01-curves.png), [02-residuals](figures/02-residuals.png), [03-spectra](figures/03-spectra.png), drawn
  from `curves/` and the file's own tables.

Headline numbers: the curves climb to 1.59 (red), 1.76 (green) and 2.06 (blue)
above their bases; base density 0.212, 0.628 and 0.842; γ 0.530, 0.541 and 0.615
per decade; residuals 0.0064, 0.0042 and 0.0099 — the tightest set in the series;
layer sensitivities peak at 625, 550 and 465 nm; MTF σ 4.84, 3.07 and 3.44 µm;
the mask runs from 0.836 of a density at 445 nm to 0.168 at the red end. At the
sheet's printed reference exposure — an 18 per cent grey card at EI 160 — the
green record sits 0.682 above its base, the lowest in the family and what a
slower negative should read. Grain is not claimed: the sheet publishes a Print
Grain Index and says it cannot be compared to rms granularity. The dye shapes are
borrowed from the VISION3 500T digitisation.

Data and prose: CC BY-SA 4.0. See [../LICENSE](../LICENSE) and
[../NOTICE.md](../NOTICE.md).
