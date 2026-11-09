# Kalofilm — film stocks as data

Twenty-one films, each measured from its manufacturer's data sheet and from real
film, packed into one file per film.

| film | process | paper it is printed on | what is measured |
|---|---|---|---|
| [FUJICHROME PROVIA 100F](provia-100f/) | E-6 reversal | none — the film is the picture | curves, three dyes, layer sensitivities, MTF, granularity |
| [FUJICOLOR PRO 400H](fuji-pro400h/) | C-41 negative | RA-4 paper | curves, four layer sensitivities, orange mask, MTF, two of three grain values |
| [KODAK EKTACHROME E100](ektachrome-e100/) | E-6 reversal | none — the film is the picture | curves, three dyes, layer sensitivities, per-layer MTF, granularity |
| [FUJICHROME VELVIA 50](velvia-50/) | E-6 reversal | none — the film is the picture | curves, three dyes, layer sensitivities, MTF, granularity |
| [KODAK PROFESSIONAL PORTRA 400](portra-400/) | C-41 negative | RA-4 paper | curves, layer sensitivities, orange mask, MTF; dyes borrowed, grain not claimed |
| [KODAK PROFESSIONAL PORTRA 800](portra-800/) | C-41 negative | RA-4 paper | curves, layer sensitivities, orange mask, MTF; dyes borrowed, grain not claimed |
| [KODAK TRI-X 400](trix-400/) | B&W negative | RA-4 paper | curve, grain, MTF; the sensitivity and MTF are the old 5063 emulsion's, which the sheet states |
| [ILFORD HP5 PLUS](hp5-plus/) | B&W negative | RA-4 paper | curve only — no sensitivity chart, no MTF, no granularity figure in the sheet |
| [KODAK PROFESSIONAL EKTAR 100](ektar-100/) | C-41 negative | RA-4 paper | curves, layer sensitivities, orange mask, MTF; dyes borrowed, grain not claimed |
| [KODAK PROFESSIONAL PORTRA 160](portra-160/) | C-41 negative | RA-4 paper | curves, layer sensitivities, orange mask, MTF; dyes borrowed, grain not claimed |
| [KODAK GOLD 200](gold-200/) | C-41 negative | RA-4 paper | curves, layer sensitivities, orange mask; dyes and blur borrowed, grain not claimed |
| [KODAK PROFESSIONAL T-MAX 400](tmax-400/) | B&W negative | RA-4 paper | curve, layer sensitivity, MTF, grain — nothing borrowed |
| [ILFORD DELTA 400](delta-400/) | B&W negative | RA-4 paper | curve; no MTF, no grain figure, no sensitivity chart — three declared absences |
| [KODAK VISION3 500T](vision3-500t/) | ECN-2 negative | RA-4 paper | curves, layer sensitivities, dyes, orange mask, grain — nothing borrowed |
| [FUJICOLOR C200](fuji-c200/) | C-41 negative | RA-4 paper | curves, layer sensitivities, MTF; dyes, mask and grain borrowed |
| [FUJIFILM 200](fuji-200/) | C-41 negative | RA-4 paper | curves, layer sensitivities; dyes, mask, blur borrowed, grain placeholder |
| [FUJIFILM 400](fuji-400/) | C-41 negative | RA-4 paper | curves, layer sensitivities; dyes, mask, blur borrowed, grain placeholder |
| [FUJICOLOR NPH 400](fuji-nph400/) | C-41 negative | RA-4 paper | curves, four layer sensitivities, grain; dyes and mask borrowed |
| [KODAK VISION3 50D](vision3-50d/) | ECN-2 negative | RA-4 paper | curves, layer sensitivities, MTF; grain, dyes and mask borrowed |
| [KODAK VISION3 200T](vision3-200t/) | ECN-2 negative | RA-4 paper | curves, layer sensitivities, MTF; grain, dyes and mask borrowed |
| [KODAK VISION3 250D](vision3-250d/) | ECN-2 negative | RA-4 paper | curves, layer sensitivities, MTF; grain, dyes and mask borrowed |

A `.kalofilm` file is the film: a header that says where every number came from,
the spectra as binary tables, and a SHA-256 over the lot. It is about 6 kB. The format
is specified in [FORMAT.md](FORMAT.md).

## What a film directory holds

```
provia-100f/
  provia-100f.kalofilm   the film: header, tables, digest
  README.md              landing page: what it is, headline numbers, links
  REPORT.md              the research report: abstract, methods, results,
                         uncertainty, references
  curves/                the digitised characteristic points, one CSV per layer
  figures/               01-curves, 02-residuals, 03-spectra — regenerated
                         from the two above
```

The points are published so the fit can be **recomputed rather than believed**:
the report's residual is against those files. The figures are plots of the same
numbers; `tools/kalofilm.py --csv` exports the spectra in the form any plotting
tool reads, so every figure can be redrawn from the data. No image of a data
sheet is reproduced anywhere here — the sheets stay with their publishers, and
the numbers are what this project produced.

## Loading one

```bash
kalo render frame.tif -o print.png --film-file films/fuji-pro400h/fuji-pro400h.kalofilm
```

A file and the stock of the same name compiled into the binary render
**byte-identical** images; a test holds them to it. `films/tools/kalofilm.py`
checks a file's digest and prints its `[measured]` section without needing the
renderer at all.

## The honesty section

Every file carries a `[measured]` table that says, field by field, whether the
number was measured or borrowed — and from where. PRO 400H's file says, in so
many words, that its dye shapes are borrowed from the VISION3 500T
digitisation and that the fourth layer's inhibitor strength is a placeholder.
A film file that hides its borrowings is one that lies about them.

## Licence

The `.kalofilm` files, the digitised curves, the figures and the prose in this
directory are licensed **CC BY-SA 4.0** — share them, adapt them, sell them, but
keep them open. The full text is in [LICENSE](LICENSE), which also records that
the three films published before 2026-11-09 went out under CC BY 4.0 and that
those copies keep that grant.

Code that reads them lives in the repository and is MIT or Apache-2.0: the
licence on
the data does not reach the renderer. See [NOTICE.md](NOTICE.md) for trademarks
and what is not redistributed.

## Citing

If a published result uses these files, cite the data sheet each film names in
its own README and the file itself, e.g.

> Kallotype `fuji-pro400h.kalofilm`, digitised from FUJIFILM product information
> bulletin AF3-176E (2026).
