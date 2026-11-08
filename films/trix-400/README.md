# KODAK TRI-X 400

The first silver film in this series, and the first `.kalofilm` that carries one
record instead of three.

- **The report:** [REPORT.md](REPORT.md) — which of the four development times
  the stock uses, why two of its curves belong to the previous emulsion, the
  grain number inverted from rms 17, and what a monochrome film does to a format
  built for colour.
- **The film:** `trix-400.kalofilm` (5,527 bytes) — load it with
  `kalo render --film-file`.
- **The points:** `curves/` — 128 points, the same curve in all three files,
  because a silver image has one record.
- **The figures:** `figures/` — `01-curves`, `02-residuals`, `03-spectra`.

Headline numbers: the curve climbs to 1.49 above a base of 0.262; γ 0.546 per
decade; residual 0.0049; the toe is soft (rate 3) and the shoulder is not (8);
at 18 per cent grey the density is 0.554 above base and the speed point is half a
stop late. Grain **0.1124 grains/µm²**, inverted from the sheet's diffuse rms
granularity of 17 at a net density of 1.0 — the coarsest in the tree. MTF σ
4.06 µm. No dyes, no mask.

The MTF and the spectral sensitivity are the **old 5063 emulsion's** data, which
the sheet states in a note; the file says so in its `[measured]` table too.

Data and prose: CC BY-SA 4.0. See [../LICENSE](../LICENSE) and
[../NOTICE.md](../NOTICE.md).
