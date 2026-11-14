import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kallo/lab/print_marker.dart';
import 'package:kallo/lab/print_meta.dart';
import 'package:kallo/lab/stock.dart';

void main() {
  late Directory root;
  final DateTime printed = DateTime.utc(2026, 11, 14, 9, 5);
  final PrintMeta meta = PrintMeta(
    id: '50f6c8d0-3e5f-4b1a-9f8e-2f5c6d7e8a9b',
    title: 'A print',
    kind: PrintKind.print,
    printed: printed,
    added: printed.add(const Duration(minutes: 1)),
    updated: printed.add(const Duration(minutes: 2)),
    process: FilmProcess.negative,
    film: 'KODAK PORTRA 400',
    paper: 'KODAK CRYSTAL',
    minutes: 9.5,
    tempC: 20,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kallo-marker-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('a PNG keeps its pixels and gains one record', () async {
    final File source = File('${root.path}/source.png');
    final img.Image picture = img.Image(width: 7, height: 5);
    img.fill(picture, color: img.ColorRgb8(180, 40, 20));
    await source.writeAsBytes(img.encodePng(picture));

    final ScannedPrint? plain = await PrintMarker.read(source);
    expect(plain?.format, PrintImageFormat.png);
    expect(plain?.pixels.width, 7);
    expect(plain?.pixels.height, 5);
    expect(plain?.meta, isNull);

    final File destination = File('${root.path}/print.png');
    await PrintMarker.write(source, destination, meta);
    expect(await source.length(), img.encodePng(picture).length);

    final ScannedPrint? scanned = await PrintMarker.read(destination);
    expect(scanned?.format, PrintImageFormat.png);
    expect(scanned?.pixels.width, 7);
    expect(scanned?.meta, meta);

    final Map<String, Uint8List> before = _pngChunks(
      await source.readAsBytes(),
    );
    final Map<String, Uint8List> after = _pngChunks(
      await destination.readAsBytes(),
    );
    expect(after['IDAT'], before['IDAT']);
    expect(_crcsAreValid(await destination.readAsBytes()), isTrue);
    expect(_pngChunkOrder(await destination.readAsBytes()), <String>[
      'IHDR',
      'iTXt',
      'IDAT',
      'IEND',
    ]);
  });

  test('a JPEG keeps its scan data and gains one record', () async {
    final File source = File('${root.path}/source.jpg');
    final img.Image picture = img.Image(width: 7, height: 5);
    img.fill(picture, color: img.ColorRgb8(20, 80, 160));
    await source.writeAsBytes(img.encodeJpg(picture, quality: 90));

    final ScannedPrint? plain = await PrintMarker.read(source);
    expect(plain?.format, PrintImageFormat.jpeg);
    expect(plain?.pixels.width, 7);
    expect(plain?.pixels.height, 5);
    expect(plain?.meta, isNull);

    final File destination = File('${root.path}/print.jpg');
    await PrintMarker.write(source, destination, meta);
    final ScannedPrint? scanned = await PrintMarker.read(destination);
    expect(scanned?.format, PrintImageFormat.jpeg);
    expect(scanned?.meta, meta);
    expect(scanned?.pixels.width, 7);

    final Uint8List sourceBytes = await source.readAsBytes();
    final Uint8List destBytes = await destination.readAsBytes();
    expect(_sosTail(destBytes), _sosTail(sourceBytes));
    expect(destBytes.length, greaterThan(sourceBytes.length));
  });

  test('finalize leaves the final name only after the marker', () async {
    final File source = File('${root.path}/source.png');
    final img.Image picture = img.Image(width: 3, height: 2);
    img.fill(picture, color: img.ColorRgb8(1, 2, 3));
    await source.writeAsBytes(img.encodePng(picture));
    final File finalFile = File('${root.path}/final.png');

    await PrintMarker.finalize(source, finalFile, meta);
    expect(await finalFile.exists(), isTrue);
    expect((await PrintMarker.readMeta(finalFile))?.id, meta.id);
    expect(
      root.listSync().whereType<File>().where((File file) {
        return file.path.endsWith('.tmp');
      }),
      isEmpty,
    );
  });

  test('unsupported files are not prints', () async {
    final File file = File('${root.path}/notes.txt');
    await file.writeAsString('not a picture');
    expect(await PrintMarker.read(file), isNull);
  });
}

Map<String, Uint8List> _pngChunks(Uint8List bytes) {
  final Map<String, Uint8List> chunks = <String, Uint8List>{};
  int at = 8;
  while (at + 12 <= bytes.length) {
    final int length = _u32(bytes, at);
    final String type = String.fromCharCodes(bytes.sublist(at + 4, at + 8));
    if (at + 12 + length > bytes.length) {
      break;
    }
    chunks[type] = Uint8List.sublistView(bytes, at + 8, at + 8 + length);
    at += 12 + length;
    if (type == 'IEND') {
      break;
    }
  }
  return chunks;
}

List<String> _pngChunkOrder(Uint8List bytes) {
  final List<String> order = <String>[];
  int at = 8;
  while (at + 12 <= bytes.length) {
    final int length = _u32(bytes, at);
    final String type = String.fromCharCodes(bytes.sublist(at + 4, at + 8));
    order.add(type);
    at += 12 + length;
    if (type == 'IEND') {
      break;
    }
  }
  return order;
}

bool _crcsAreValid(Uint8List bytes) {
  int at = 8;
  while (at + 12 <= bytes.length) {
    final int length = _u32(bytes, at);
    final List<int> typeAndData = bytes.sublist(at + 4, at + 8 + length);
    final int expected = _u32(bytes, at + 8 + length);
    if (_crc32(typeAndData) != expected) {
      return false;
    }
    final String type = String.fromCharCodes(bytes.sublist(at + 4, at + 8));
    at += 12 + length;
    if (type == 'IEND') {
      break;
    }
  }
  return true;
}

Uint8List _sosTail(Uint8List bytes) {
  for (int i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] == 0xff && bytes[i + 1] == 0xda) {
      return Uint8List.sublistView(bytes, i);
    }
  }
  throw StateError('no SOS in JPEG');
}

int _u32(Uint8List bytes, int at) =>
    (bytes[at] << 24) |
    (bytes[at + 1] << 16) |
    (bytes[at + 2] << 8) |
    bytes[at + 3];

int _crc32(List<int> bytes) {
  int crc = 0xffffffff;
  for (final int byte in bytes) {
    crc ^= byte;
    for (int k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}
