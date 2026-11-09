# FUJICHROME PROVIA 100F (RDP III)

An E-6 colour reversal whose curves, three dyes, layer sensitivities, MTF and
granularity are all from its own sheet.

- **The report:** [REPORT.md](REPORT.md) — the vector-path reading, the
  three-plate decomposition and its residual cost, the fits, uncertainty.
- **The film:** `provia-100f.kalofilm` (5,444 bytes) — load it with
  `kalo render --film-file`.
- **The points:** `curves/` — 768, 183 and 320 digitised points.
- **The figures:** [01-curves](figures/01-curves.png), [02-residuals](figures/02-residuals.png), [03-spectra](figures/03-spectra.png), drawn
  from `curves/` and the file's tables.

Headline numbers: γ 2.08 on all three layers; sensitivities read from the
Bézier paths at 455, 543 and 642 nm; dyes at 443, 543 and 658 nm; σ 4.68 µm;
grain 3.95 grains/µm² inverted from the sheet's published rms granularity of 8,
at the density that granularity was measured at.

Data and prose: CC BY-SA 4.0. See [../LICENSE](../LICENSE) and
[../NOTICE.md](../NOTICE.md).
