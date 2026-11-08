# KODAK PROFESSIONAL EKTACHROME E100

An E-6 colour reversal whose curves, three dyes, three layer sensitivities,
per-layer MTF and granularity all come from its own sheet.

- **The report:** [REPORT.md](REPORT.md) — the plot box that rules nothing, the
  anchor solved as a density, the two-lobe residual and what a second transition
  would buy.
- **The film:** `ektachrome-e100.kalofilm` (5,667 bytes) — load it with
  `kalo render --film-file`.
- **The points:** `curves/` — 128 digitised points per layer.
- **The figures:** `figures/` — `01-curves`, `02-residuals`, `03-spectra`, drawn
  from `curves/` and the file's tables.

Headline numbers: γ 2.22, 2.48 and 2.55; unexposed film 3.35, 3.73 and 3.91
against a clear density of 0.18–0.19; sensitivities peaking at 645, 545 and
425 nm; dyes at 445, 545 and 660 nm; σ 5.40, 4.31 and 3.81 µm — one per layer,
which no other sheet here publishes; grain 8.32 grains/µm² inverted from the
sheet's rms granularity of 8.

Its anchor puts the film's 18 % grey at a density of `d_max + 0.745`, and the
exposure that reaches it lands within 0.035 decade of the independent answer
FUJICHROME PROVIA 100F gives from its own sheet — two manufacturers, one rule.

Data and prose: CC BY 4.0. See [../LICENSE](../LICENSE) and
[../NOTICE.md](../NOTICE.md).
