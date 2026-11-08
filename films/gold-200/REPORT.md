# KODAK GOLD 200: the negative base density

*Kallotype film-data series, report 11 of 16. Version 1, 2026-11-09.
Data: `gold-200.kalofilm` (6,237 bytes). Code: `films/tools/`.*

## Abstract

We digitise KODAK GOLD 200, a consumer C-41 colour negative, from the three
panels on page 4 of E-7022 and release it as a 6.2 kB data file. It is the
cheapest sheet in the archive and the one that gave the fitter its clearest
absurdity to fix.

**The base that was negative.** The old fit left the blue curve's asymptote at
2.782 against a drawn top of 2.751 — 0.03 *above* the ink — and to reach that
height it put the layer's base density at **−0.042**. A film cannot have less
than no density. The stock file pinned the base to zero and carried 0.994
separately, so its curve and its base described two different films at the bottom
of the curve, and the residual it declared (0.0450) was the damage rather than
the fit. `--rising` bounds the asymptote from below by the highest drawn density;
the base lands at **0.9843** against an ink floor of 0.9709, and the residual
falls to **0.0059 / 0.0060 / 0.0095**.

**The anchor.** E-7022 prints `Log H Ref: −1.14`, which is what
`log10(0.8 / S) + 1.26` gives for S = 200. The shift is **+0.3953**, against
+0.2076 for the corner midpoint the stock used before — 0.188 decade, 0.62 of a
stop.

**The mask.** The dye panel's lower curve is D-min, the model's mask, and the
stock now carries its own (**0.996** of a density at 440 nm, 0.238 at the red
end) instead of borrowing VISION3's. It is the densest base in the Kodak family,
which is what an ISO 200 consumer film's yellow layer looks like. Grain is not
claimed: the sheet publishes a Print Grain Index and says the index cannot be
compared to rms granularity. Blur is not claimed either — this sheet has no MTF
panel at all.

## 1. Introduction

GOLD 200 is the consumer end of the Kodak range: three panels of artwork instead
of four, a characteristic chart whose own title is just "CURVES", and a
sensitivity plot drawn as separate short marks rather than continuous paths. It
was derived during the colour-negative survey, with the pre-correction fit, the
corner-midpoint anchor and the borrowed mask; this report replaces that version.

What it adds to the family is a demonstration of what an unconstrained asymptote
does to a *base density*. On the three professional negatives the same defect
cost a few hundredths of a density at the top of the curve; here it cost the
sign of the base.

## 2. Materials

**The data sheet.** KODAK GOLD 200 Film, publication E-7022, revised 06-23 (June
2023), page 4, retrieved 2026-11-08, SHA-256 `8f20aa3c…5f062`. Page 4 carries
three panels; the other three pages carry exposure tables, a reciprocity table
and the Print Grain Index.

**The artwork.** Page 4 is entirely vector: 151 drawing objects, not one embedded
image. The characteristic curves are three paths of 14 to 27 items, some of them
cubics; the sensitivity panel is 65–70 short marks, and the reader stitches them
by endpoint continuity.

| panel | frame (pt) | axes |
|---|---|---|
| curves (untitled "CURVES") | 184 × 184 | log H −3.0…+1.0, density 0.0…4.0 |
| spectral sensitivity | 239 × 212 | 250…750 nm, log sensitivity 0.0…4.0 |
| spectral dye density | 184 × 184 | 400…700 nm, density 0.0…2.5 |

There is **no modulation transfer function** anywhere in the four pages, so
`emulsion.sigma_um` is borrowed and cannot become measured; the file says so in
`[measured]` and in its own `[stock] note`.

Calibration comes from the page's own tick labels: 0.01 log units in x and 0.008
of a density in y on the characteristic panel, 0.01 and 0.007 on the dye panel.
The characteristic panel's x labels print without their minus signs; the tick
positions are monotone and the reader recovers the signs from them.

## 3. Methods

### 3.1 The fit: a base density cannot be negative

The model's curve is a trapezoid of two softplus corners. On a negative the curve
climbs and the sheet stops drawing before the shoulder, so the top of the
trapezoid is not measured — only bounded by the highest density the sheet draws.
The old fit had no such bound and used the freedom to flatten the curve early;
for blue it then had to reach 2.782 with an amplitude that left the bottom at
−0.042.

The stock file's response was to pin the curve's `d_min` to zero and carry 0.994
as the base — which is how the format works, since the model's curve is the dye
*above* base. But pinning hides the problem rather than fixing it: the curve that
was fitted and the curve that ships differ by 0.042 everywhere, and the shipped
one's residual (0.0450) is that difference, not the fit's.

`--rising` bounds the asymptote from below by the highest drawn density and
`--asymptote-window 0.02` keeps it within 0.02 of that point. The blue base comes
out at **0.9843**, just under the ink's floor of 0.9709, and the residuals become
**0.0059 / 0.0060 / 0.0095**.

**How much headroom?** The bound is a decision; a larger window buys little:

| window above the drawn top | red | green | blue | rms (r/g/b) |
|---|---|---|---|---|
| 0.02 | 1.844 | 2.329 | 2.754 | 0.0059 / 0.0060 / 0.0095 |
| 0.05 | 1.885 | 2.346 | 2.793 | 0.0054 / 0.0045 / 0.0091 |
| 0.10 | 1.885 | 2.346 | 2.801 | 0.0054 / 0.0045 / 0.0089 |

A tenth of a density of headroom moves the residual by 0.0005 to 0.0015 and the
base density with it; red and green have already stopped moving at 0.05, which is
the corner grid's own resolution showing through. The base is a
physical quantity that the model uses in both print paths, so it is the one
number that must not be bought with invented headroom. The smallest defensible
window is kept.

**The corner rates.** 5/4 for red, 4/3 for green, 10/4 for blue. The green
record's 4/3 is the lowest pair in the family: the curves turn gently and the fit
prefers soft corners at both ends, which is what a consumer film's shoulder looks
like next to PORTRA 400's.

### 3.2 Reading curves that are drawn in cubics

Each characteristic path here carries four to six cubic Bézier segments. The
reader used to keep only each cubic's end point, a chord through the curve, and
on this sheet that put the red and green curves up to 0.05 of a density away from
their own artwork. It now evaluates each cubic at twelve points; the residuals
above are against the artwork.

### 3.3 The anchor: the sheet prints one

Above the characteristic panel is the line

    Exposure: Daylight   Densitometry: Status M   Log H Ref: −1.14

`Log H Ref` is the log exposure an 18 per cent grey card receives at the film's
rated speed, and for S = 200 the family formula gives −1.1379, which is what the
sheet prints. The model exposes mid grey at log10(0.18) = −0.7447, so the axis is
shifted by **+0.3953** — one number for all three layers, so relative layer
speeds are untouched.

The stock used to be anchored on the fitted corner midpoint (shift +0.2076). The
two anchors are 0.188 decade apart, 0.62 of a stop; the printed one is the
measurement.

**The check.** At the anchor the three records sit 0.669, 0.745 and 0.761 of a
density above their fitted bases. A C-41 negative is balanced for a green-record
density of about 0.70 above D-min at 18 per cent grey, and this film reads 0.745
— the highest in the family, which is what a consumer negative's slightly heavier
mid-scale tone looks like.

**The speed point closes here.** At 1.26 decades below the reference the green
record reads +0.098 where the standard asks for +0.10: **0.04 of a stop** from
the rating, the only Kodak sheet in the tree whose curve matches its ISO speed.
The others sit 0.6 to 0.7 of a stop late, and no sheet in the archive explains
why this one does not.

### 3.4 The mask is this sheet's own

The dye panel is headed *Spectral-Dye-Density Curves* and draws two curves,
**Midscale Neutral** and **Minimum Density**. No Kodak still-film sheet in the
archive publishes three dye curves, so the dye *shapes* stay borrowed from the
VISION3 500T digitisation and the file's `[measured]` table says so.

The lower curve is D-min — the model's mask, base, fog and orange mask as a
spectrum. It is read from 400 to 699 nm, put on the model's 380–730 nm grid by
repeating the end values (`resample_mask.py`), and it runs **0.238 to 0.996**,
peaking at 440 nm and least at 630.

The fitted bases (0.255, 0.644, 0.984) agree with the mask to 0.02: 0.002 at the
cyan dye's 650 nm, 0.002 at the magenta dye's 550, and 0.012 under the mask's
440 nm peak, which is where the blue record's Status M density is set. The
densest base in the family is also its best-measured one, because the blue
record's weighting and the mask's peak fall on the same wavelength.

### 3.5 Sensitivity, the borrowed blur, and the grain that is not there

**Sensitivity.** Three forming layers on a 250–750 nm axis, drawn as marks cut
every 4 pt rather than as continuous paths, stitched by their ends. Stored as
`10^logS` on the sheet's own scale, the peaks are 214.7 at 470 nm (yellow-forming,
the blue record), 177.6 at 550 (magenta, green) and 167.9 at 650 (cyan, red).
That is the flattest set of peaks in the family: the three are within 28 per cent
of each other, where EKTAR 100's span a factor of 1.9 and PORTRA 400's 1.2.

**Blur.** There is no MTF panel, so the file borrows the compiled blur and
`[measured]` reads `mtf = "borrowed: the sheet has three panels and none of them
is a modulation transfer function"`. The alternative — fitting the sheet's
sharpness claim from page 1 — would be a number with no chart behind it.

**Grain.** The sheet prints a Print Grain Index table and states that the index
"replaces rms granularity and has a different scale which cannot be compared to
rms granularity". The file carries the compiled placeholder and says
`grain = "placeholder"`.

## 4. Results

### Table 1 — characteristic curves

| layer | base (D-min) | d_max | γ /decade | log_e0 | rates | rms |
|---|---|---|---|---|---|---|
| red | 0.2553 | 1.5884 | 0.5515 | −0.5223 | 5 / 4 | 0.0059 |
| green | 0.6442 | 1.6848 | 0.5933 | −0.5823 | 4 / 3 | 0.0060 |
| blue | 0.9843 | 1.7691 | 0.6186 | −0.5123 | 10 / 4 | 0.0095 |

`d_max` is above the base: the absolute asymptote is `base + d_max`, and
0.984 + 1.769 = 2.753 is the blue curve's ceiling on the sheet's own axis,
against a drawn top of 2.751. Residuals are against the 128 points in `curves/`.

### Table 2 — the other measurables

| quantity | value | source |
|---|---|---|
| sensitivity peaks | 470, 550, 650 nm | page 4, spectral sensitivity |
| MTF | borrowed | no MTF panel in the sheet |
| mask | 0.996 at 440 nm → 0.238 at 699 | page 4, D-min |
| dyes | borrowed | VISION3 500T digitisation |
| grain | not claimed | page 3, Print Grain Index |

### Figures

- `figures/01-curves.png` — the fits and the digitised points.
- `figures/02-residuals.png` — point minus fit, inside ±0.012 except at the ends,
  where the sheet is still climbing and the bounded asymptote has begun to
  flatten.
- `figures/03-spectra.png` — the three layer sensitivities, the three borrowed
  dyes and the film's own mask.

## 5. What is measured and what is decided

Measured: the three curve shapes, the layer sensitivities, the mask, and the
anchor the sheet prints.

Decided:

1. **The 0.02-density asymptote window.** It is what keeps the base density
   positive and physical; §3.1 shows what a larger window would buy and why it is
   not bought.
2. **The corner rates**, extrapolated beyond the frame.
3. **The mask's ends**, held flat outside the drawn span.
4. **The borrowed dyes**, because the sheet prints a neutral and D-min.
5. **The borrowed blur**, because the panel does not exist.
6. **The unclaimed grain**, because the sheet forbids the conversion.

## 6. Uncertainty and limits

The curves are drawn coarsely — 14 to 27 items over 3.9 decades — and the chord
reading of §3.2 cost up to 0.05 of a density before it was corrected. The fit now
uses the artwork, and the residuals are 0.006 to 0.010, at the y calibration's
0.008.

The base densities are the fit's asymptotes. On this film that matters more than
on the others because the blue base is the largest number of its kind in the
family and is used by both print paths; the window table in §3.1 is the honest
statement of how much freedom it has. The mask is measured independently and
agrees to 0.012, which is the check that the base is not a fit artefact.

The film borrows two of the five measured quantities the format asks for — blur
and dyes — and does not claim a third. It is still worth a file: a model that
only accepted films whose sheets publish every chart would accept four of the
twenty-six stocks in the catalogue.

## 7. Availability and reproduction

`gold-200.kalofilm` carries the header, the tables and a SHA-256;
`kalo render --film-file` loads it. The figures are regenerated from `curves/`
and the file with

```bash
python3 ../tools/kalofilm.py --check gold-200.kalofilm      # magic, digest, sizes
python3 ../tools/kalofilm.py --csv /tmp/film gold-200.kalofilm
```

The points in `curves/` are in the model's exposure frame — the sheet's log H
shifted by +0.3953 — and carry absolute Status M density, base included;
`curves/README.md` states the shift so the fit can be recomputed from the sheet's
own axis.

No image of the data sheet is reproduced in this directory.

## References

1. Eastman Kodak Company, *KODAK GOLD 200 Film*, publication E-7022, revised
   06-23, page 4.
2. Kallotype, *The `.kalofilm` format, version 1*, `../FORMAT.md`.
3. Kallotype, `films/portra-400/REPORT.md` — the report that introduced the
   rising fit.
