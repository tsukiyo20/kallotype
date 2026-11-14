import 'package:flutter_test/flutter_test.dart';
import 'package:kallo/lab/print_meta.dart';
import 'package:kallo/lab/stock.dart';
import 'package:kallo/lab/print_xmp.dart';

void main() {
  final DateTime printed = DateTime.utc(2026, 11, 14, 9, 5);
  final PrintMeta meta = PrintMeta(
    id: '50f6c8d0-3e5f-4b1a-9f8e-2f5c6d7e8a9b',
    title: '暗房 · print 01',
    kind: PrintKind.print,
    printed: printed,
    added: printed.add(const Duration(hours: 1)),
    updated: printed.add(const Duration(hours: 2)),
    printNumber: 3,
    process: FilmProcess.negative,
    film: 'KODAK PORTRA 400',
    paper: 'KODAK CRYSTAL',
    minutes: 9.5,
    tempC: 20,
  );

  test('a record survives an XMP round trip', () {
    final String packet = PrintXmp.encode(meta);
    expect(packet, contains('kallo:id'));
    expect(packet, contains('dc:title'));
    expect(packet, contains('暗房'));

    final PrintMeta? decoded = PrintXmp.decode(packet);
    expect(decoded, isNotNull);
    expect(decoded, meta);
  });

  test('a non-Kallo packet is not a print', () {
    const String packet =
        '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF '
        'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
        '<rdf:Description rdf:about="" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title><rdf:Alt><rdf:li xml:lang="x-default">Other</rdf:li>'
        '</rdf:Alt></dc:title></rdf:Description></rdf:RDF></x:xmpmeta>';
    expect(PrintXmp.looksLikeKallo(packet), isFalse);
    expect(PrintXmp.decode(packet), isNull);
  });

  test('merging preserves another namespace', () {
    const String existing =
        '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF '
        'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
        '<rdf:Description rdf:about="" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/">'
        '<dc:title><rdf:Alt><rdf:li xml:lang="x-default">Old</rdf:li>'
        '</rdf:Alt></dc:title>'
        '<photoshop:City>Shanghai</photoshop:City>'
        '</rdf:Description></rdf:RDF></x:xmpmeta>';

    final String merged = PrintXmp.merge(existing, meta);
    expect(merged, contains('Shanghai'));
    expect(merged, contains('kallo:id'));
    expect(merged, contains('暗房'));

    final PrintMeta? decoded = PrintXmp.decode(merged);
    expect(decoded?.id, meta.id);
  });

  test('merging a Kallo packet replaces only the Kallo description', () {
    final String first = PrintXmp.encode(meta);
    final PrintMeta other = meta.copyWith(
      title: 'second',
      film: 'ILFORD HP5 PLUS',
    );
    final String merged = PrintXmp.merge(first, other);
    expect(merged, contains('second'));
    expect(merged, isNot(contains('KODAK PORTRA 400')));

    final PrintMeta? decoded = PrintXmp.decode(merged);
    expect(decoded?.title, 'second');
    expect(decoded?.film, 'ILFORD HP5 PLUS');
  });

  test('dates without a timezone still parse', () {
    final String packet = PrintXmp.encode(meta).replaceFirst(
      'kallo:printed="2026-11-14T09:05:00.000Z"',
      'kallo:printed="2026-11-14T09:05:00"',
    );
    final PrintMeta? decoded = PrintXmp.decode(packet);
    expect(decoded?.printed, isNotNull);
  });
}
