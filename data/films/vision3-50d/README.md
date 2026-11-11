# KODAK VISION3 50D

The slow daylight cinema stock: five raster charts on two pages, a dotted red
curve, a sensitivity axis whose printed numbers do not sit on its own ticks, and
the softest MTF of the three VISION3 films.

- **The report:** [REPORT.md](REPORT.md) — the dotted curve, the mislabelled
  sensitivity axis, the dye set the model shares with the 500T, and the
  granularity chart the tracker cannot read.
- **The film:** `vision3-50d.kalofilm` (5,759 bytes) — load it with
  `kalo render --film-file`.
- **The points:** `curves/` — 349 points for red, 538 for green and blue.
- **The figures:** [01-curves](figures/01-curves.png), [02-residuals](figures/02-residuals.png), [03-spectra](figures/03-spectra.png), drawn
  from `curves/` and the file's own tables.

Headline numbers: the curves climb to 1.72 (red), 2.06 (green) and 1.99 (blue)
above their bases; base 0.176, 0.580 and 0.848; γ 0.494, 0.582 and 0.566 per
decade; residuals 0.0065, 0.0042 and 0.0053; layer sensitivities peak at 650,
550 and 465 nm; MTF σ 4.53, 4.41 and 4.26 µm. At mid grey the negative sits 0.61
to 0.70 of a density above base. Grain, dyes and the mask are borrowed from the
500T digitisation, and the file says why.

Data and prose: CC BY-SA 4.0. See [../LICENSE](../LICENSE) and
[../NOTICE.md](../NOTICE.md).
