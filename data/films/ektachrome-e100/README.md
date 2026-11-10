# KODAK PROFESSIONAL EKTACHROME E100

An E-6 colour reversal whose curves, three dyes, three layer sensitivities,
per-layer MTF and granularity all come from its own sheet.

- **The report:** [REPORT.md](REPORT.md) — the plot box that rules nothing, the
  anchor solved as a density, the two-lobe residual and what a second transition
  would buy.
- **The film:** `ektachrome-e100.kalofilm` (5,667 bytes) — load it with
  `kalo render --film-file`.
- **The points:** `curves/` — 128 digitised points per layer.
- **The figures:** [01-curves](figures/01-curves.png), [02-residuals](figures/02-residuals.png), [03-spectra](figures/03-spectra.png), drawn
  from `curves/` and the file's tables.

Headline numbers: γ 2.57, 2.90 and 2.98 with the corners turning at 5 per decade
at the toe and 2.5 at the shoulder; unexposed film 3.28, 3.65 and 3.81 against a
clear density of 0.048–0.053; sensitivities peaking at 645, 545 and 425 nm;
dyes at 445, 545 and 660 nm; σ 5.40, 4.31 and 3.81 µm — one per layer, which no
other sheet here publishes; grain 3.61 grains/µm² inverted from the sheet's rms
granularity of 8 *at the density it was measured at*.

It is the stock that made the model carry a corner rate for the toe and another
for the shoulder, and the report's section 5 is the story of getting that right
in three readings — two of them wrong. Its clear density is an extrapolation
either way: the sheet stops drawing while the curve is still falling, which is
also why its anchor lands 0.118 decade from PROVIA's rather than the 0.035 the
first fit suggested.

Data and prose: CC BY-SA 4.0. See [../LICENSE](../LICENSE) and
[../NOTICE.md](../NOTICE.md).
