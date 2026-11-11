import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kallo_ui/lab/model.dart';
import 'package:kallo_ui/lab/stock.dart';

/// A catalogue in the shape `kalo stocks --json` writes, cut down to the keys
/// the app reads. Two films and a paper is enough to prove the document is
/// parsed the way the app reads it; the document itself is the model's, and the
/// integration test asks a real binary for one.
const String _document = '''
{
  "films": [
    {
      "id": "kodak_portra_400",
      "short": "PORTRA 400",
      "label": "KODAK PROFESSIONAL PORTRA 400",
      "process": "negative",
      "note": "Measured: the characteristic curves.",
      "reference": {"minutes": 6.5, "temp_c": 20.0},
      "provenance": {
        "publication": "E-4050",
        "page": "4",
        "retrieved": "2026-11-08",
        "checksum": "sha256:e83a"
      },
      "measured": [
        {"field": "curves", "claim": "measured", "detail": "page 4, three curves"},
        {"field": "grain", "claim": "placeholder", "detail": ""}
      ]
    },
    {
      "id": "provia_100f",
      "short": "PROVIA 100F",
      "label": "FUJICHROME PROVIA 100F (RDP III), E-6",
      "process": "reversal"
    }
  ],
  "papers": [
    {
      "id": "fuji_crystal_archive_pearl",
      "short": "CRYSTAL ARCHIVE PEARL",
      "label": "FUJICOLOR CRYSTAL ARCHIVE DIGITAL PEARL PAPER, RA-4"
    }
  ]
}
''';

void main() {
  final Catalogue catalogue = Catalogue.fromJson(
    jsonDecode(_document) as Map<String, dynamic>,
  );

  test('a stock arrives with its box name, its sheet and its borrows', () {
    final Stock? portra = catalogue.film('kodak_portra_400');
    expect(portra, isNotNull);
    expect(portra!.short, 'PORTRA 400');
    expect(portra.label, 'KODAK PROFESSIONAL PORTRA 400');
    expect(portra.process, FilmProcess.negative);
    expect(portra.referenceMinutes, 6.5);
    expect(portra.referenceTempC, 20);
    expect(portra.provenance.publication, 'E-4050');
    expect(portra.provenance.page, '4');
    expect(portra.measured.map((Measured m) => m.field), <String>['curves', 'grain']);
    expect(portra.measured.first.claim, 'measured');
    expect(portra.measured.first.detail, 'page 4, three curves');
    // A field the file said one word about: the verdict is the whole line.
    expect(portra.measured.last.claim, 'placeholder');
    expect(portra.measured.last.detail, isEmpty);
  });

  test('the shelf groups the films by chemistry', () {
    expect(catalogue.of(FilmProcess.negative), hasLength(1));
    expect(catalogue.of(FilmProcess.reversal).single.id, 'provia_100f');
    expect(catalogue.of(FilmProcess.monochrome), isEmpty);
  });

  test('papers are stocks too, and are looked up the same way', () {
    expect(
      catalogue.paper('fuji_crystal_archive_pearl')?.short,
      'CRYSTAL ARCHIVE PEARL',
    );
  });

  test('a film without a short name is called by its label', () {
    // The `short` key is optional in the format: a file that predates it is
    // still a film, and the wall label falls back rather than showing nothing.
    final Catalogue old = Catalogue.fromJson(
      jsonDecode('''
{"films": [{"id": "fuji200", "label": "FUJIFILM 200 Color Negative Film",
  "process": "negative"}]}
''') as Map<String, dynamic>,
    );
    expect(old.films.single.short, 'FUJIFILM 200 Color Negative Film');
    expect(old.films.single.measured, isEmpty);
  });

  test('no model is no catalogue: the shelf keeps the film it carries', () async {
    final Catalogue carried = await Catalogue.load(const Model(''));
    expect(carried.films, hasLength(1));
    expect(carried.films.single.id, Stocks.defaultId);
    // The paper the app prints on is carried too: a roll still needs one.
    expect(carried.papers.single.id, Stocks.paper);
    expect(carried.papers.single.short, Stocks.paperShort);
  });
}
