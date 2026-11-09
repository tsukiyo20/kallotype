# KODAK T-MAX 100: the slow panchromatic film

*Kallotype film-data series, report 23 of 23. Version 1, 2026-11-10.
Data: `kodak-tmax-100.kalofilm` (5,564 bytes). Code: `films/tools/`.*

## Abstract

KODAK PROFESSIONAL T-MAX 100 (F-4016) is the slow panchromatic film of the
catalogue and the second silver stock whose blur is measured from its own sheet.
The characteristic panel draws **three development times** — 6, 7.5 and 10
minutes in D-76 — not three colour records; the file carries the 7.5-minute
curve, Kodak's published standard, fitted at rms 0.0153, and the kinetics move
it the way every other stock's are moved.

The MTF panel gives one curve for the film, fitted here as a single Gaussian of
**1.42 µm** (rms 1.5 per cent, 87 per cent modelled against the sheet's 86 at
50 cycles/mm). No orange mask exists because a silver image has none; the layer
table is the panchromatic constant; the grain is **not claimed**, though the
sheet prints one diffuse rms number, because turning that number into grains per
square micron is the pass the other silver films got and this one has not yet.

## 1. Materials

**The data sheet.** KODAK PROFESSIONAL T-MAX 100 Film — Technical Data,
publication F-4016, page 8, retrieved 2026-11-10, SHA-256 `00518d7d…113be`.

**The panels.** Page 8 draws the D-76 characteristic curves at 6, 7.5 and 10
minutes (diffuse visual densitometry), the modulation transfer curve, the
spectral sensitivity curves and a table of resolving power and diffuse rms
granularity.

## 2. Methods

### 2.1 The curve

There is no printed reference exposure, so the film is anchored on the printing
aim — the visual record at 0.70 of a density above base at 18 per cent grey,
shift +0.4872. The fit:

| base | d_max | γ /decade | log_e0 | rates | rms |
|---|---|---|---|---|---|
| 0.2176 | 1.9618 | 0.6957 | −0.3373 | 10 / 6 | 0.0153 |

The same curve serves the three channels, because a silver image is one record;
this is what TRI-X and DELTA 400 do too.

### 2.2 The blur

The MTF is drawn on log axes, 2.4 to 146 cycles/mm. Fitted over 5–60 cycles/mm,
where one Gaussian can be held to the data, it gives **σ = 1.42 µm**, and the
model at 50 cycles/mm reads 87 per cent against the sheet's 86.

### 2.3 What is not measured

**Layers.** Flat: a silver image is panchromatic, and the sheet's sensitivity
panel is drawn against a log axis this reader could not calibrate. The three
rows carry the same constant, and the note says so.

**Grain.** The sheet prints a diffuse rms granularity of 8. Converting it needs
the same treatment TRI-X's 17 received; until that pass is done the field stays
zero rather than pretending a conversion happened.

## 3. Results

### Figures

- `figures/01-curves.png` — the fit and the digitised points.
- `figures/02-residuals.png` — point minus fit.
- `figures/03-spectra.png` — three flat lines, the file saying "panchromatic
  and unmeasured" rather than a measured curve.

## 4. What is measured and what is decided

Measured: the 7.5-minute curve and the MTF.

Decided:

1. **The 7.5-minute curve**, because the sheet draws three times and D-76's
   published standard is the middle one.
2. **The printing-aim anchor**, because the sheet prints no reference exposure.
3. **The flat layers and the unclaimed grain**, each declared.

## 5. Availability and reproduction

`kodak-tmax-100.kalofilm` carries the header, the tables and a SHA-256;
`kalo render --film-file` loads it.

```bash
python3 ../tools/kalofilm.py --check kodak-tmax-100.kalofilm
```

No image of the data sheet is reproduced in this directory.

## References

1. Eastman Kodak Company, *KODAK PROFESSIONAL T-MAX 100 Film — Technical Data*,
   publication F-4016, page 8.
2. Kallotype, `films/tmax-400/REPORT.md` — its faster sibling.
