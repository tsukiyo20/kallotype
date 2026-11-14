import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'print_meta.dart';
import 'print_xmp.dart';

/// What a file is, as far as the scanner cares.
enum PrintImageFormat { png, jpeg }

/// One image read by its header, with or without a Kallo record.
@immutable
class ScannedPrint {
  const ScannedPrint({required this.format, required this.pixels, this.meta});

  final PrintImageFormat format;
  final Size pixels;

  /// Null when the image is somebody else's picture. The catalog may still have
  /// a row for it by locator; that is the catalog's business, not this reader's.
  final PrintMeta? meta;
}

/// Read and write the Kallo record inside a PNG or JPEG.
///
/// The pixels are never decoded and never re-encoded. A PNG gets an `iTXt`
/// chunk before `IDAT`; a JPEG gets an APP1 XMP segment after `SOI` / `APP0`.
/// Everything the file already carried — EXIF, ICC, other XMP namespaces —
/// is copied through.
abstract final class PrintMarker {
  static const String _pngXmpKeyword = 'XML:com.adobe.xmp';
  static const String _jpegXmpPrefix = 'http://ns.adobe.com/xap/1.0/';
  static const int _maxHeader = 1024 * 1024;
  static const int _maxXmp = 64 * 1024;

  /// Read the header and the Kallo record without decoding pixels.
  ///
  /// Returns null for a file that is not PNG or JPEG, or whose header cannot
  /// be read. An image with no Kallo record still returns a [ScannedPrint] with
  /// a null [ScannedPrint.meta].
  static Future<ScannedPrint?> read(File file) async {
    RandomAccessFile? reader;
    try {
      reader = await file.open();
      final Uint8List signature = await reader.read(8);
      if (_isPng(signature)) {
        await reader.setPosition(0);
        return await _readPng(reader);
      }
      if (_isJpeg(signature)) {
        await reader.setPosition(0);
        return await _readJpeg(reader);
      }
      return null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } finally {
      await reader?.close();
    }
  }

  /// Read only the record, if the file has one.
  static Future<PrintMeta?> readMeta(File file) async =>
      (await read(file))?.meta;

  /// Write [meta] into [source] at [destination].
  ///
  /// [destination] is normally a temporary file; the caller renames it into
  /// place after this returns. The source is not modified.
  static Future<void> write(
    File source,
    File destination,
    PrintMeta meta,
  ) async {
    final ScannedPrint? scanned = await read(source);
    if (scanned == null) {
      throw const FormatException('the print is not a PNG or JPEG');
    }
    final RandomAccessFile input = await source.open();
    final RandomAccessFile output = await destination.open(
      mode: FileMode.write,
    );
    try {
      switch (scanned.format) {
        case PrintImageFormat.png:
          await _writePng(input, output, meta);
        case PrintImageFormat.jpeg:
          await _writeJpeg(input, output, meta);
      }
      await output.flush();
    } finally {
      await input.close();
      await output.close();
    }
  }

  /// Write a record into a temporary file beside [destination] and rename it
  /// over the final name. The final name never exists without its marker.
  static Future<void> finalize(
    File source,
    File destination,
    PrintMeta meta,
  ) async {
    final File temp = File(
      '${destination.parent.path}${Platform.pathSeparator}'
      '.${destination.uri.pathSegments.last}.kallo-${meta.id}.tmp',
    );
    try {
      await temp.parent.create(recursive: true);
      await write(source, temp, meta);
      await temp.rename(destination.path);
    } on Object {
      try {
        if (await temp.exists()) {
          await temp.delete();
        }
      } on FileSystemException {
        // A leftover temporary file is not worth masking the real failure.
      }
      rethrow;
    }
  }

  static bool _isPng(Uint8List bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a;

  static bool _isJpeg(Uint8List bytes) =>
      bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xd8;

  static Future<ScannedPrint?> _readPng(RandomAccessFile reader) async {
    final Uint8List signature = await reader.read(8);
    if (!_isPng(signature)) {
      return null;
    }
    Size? pixels;
    PrintMeta? meta;
    int traversed = 0;
    while (true) {
      final Uint8List header = await reader.read(8);
      if (header.length < 8) {
        break;
      }
      final int length = _u32(header, 0);
      final String type = String.fromCharCodes(header.sublist(4, 8));
      if (length > _maxHeader || traversed > _maxHeader) {
        break;
      }
      traversed += 12 + length;

      if (type == 'IHDR') {
        if (length < 13) {
          return null;
        }
        final Uint8List data = await reader.read(length);
        pixels = Size(_u32(data, 0).toDouble(), _u32(data, 4).toDouble());
      } else if (type == 'iTXt') {
        if (length <= _maxXmp) {
          final Uint8List data = await reader.read(length);
          final String? packet = _itxtPacket(data);
          if (packet != null) {
            meta = PrintXmp.decode(packet);
          }
        } else {
          await reader.setPosition(await reader.position() + length);
        }
      } else if (type == 'IDAT' || type == 'IEND') {
        // XMP belongs before the image data. A marker after it is not read:
        // the cost of scanning a whole image to find one is the cost this app
        // exists to avoid.
        break;
      } else {
        await reader.setPosition(await reader.position() + length);
      }
      await reader.read(4); // CRC
      if (pixels != null && meta != null) {
        break;
      }
    }
    if (pixels == null) {
      return null;
    }
    return ScannedPrint(
      format: PrintImageFormat.png,
      pixels: pixels,
      meta: meta,
    );
  }

  static Future<void> _writePng(
    RandomAccessFile input,
    RandomAccessFile output,
    PrintMeta meta,
  ) async {
    final String? existing = await _pngXmp(input);
    final String packet = existing == null
        ? PrintXmp.encode(meta)
        : PrintXmp.merge(existing, meta);
    final Uint8List chunk = _chunk('iTXt', _itxtData(packet));

    await input.setPosition(0);
    await output.writeFrom(await input.read(8));
    bool written = false;
    while (true) {
      final Uint8List header = await input.read(8);
      if (header.length < 8) {
        break;
      }
      final int length = _u32(header, 0);
      final String type = String.fromCharCodes(header.sublist(4, 8));

      if (type == 'iTXt') {
        final Uint8List data = await input.read(length);
        await input.read(4);
        final String? packet = _itxtPacket(data);
        if (packet != null) {
          // The old Kallo packet is replaced by the one at the front.
          continue;
        }
        await output.writeFrom(header);
        await output.writeFrom(data);
        await output.writeFrom(_u32Bytes(_pngCrc(type, data)));
        continue;
      }

      if (type == 'IDAT' && !written) {
        await output.writeFrom(chunk);
        written = true;
      }
      if (type == 'IEND' && !written) {
        await output.writeFrom(chunk);
        written = true;
      }

      await output.writeFrom(header);
      await _copy(input, output, length);
      final Uint8List crc = await input.read(4);
      await output.writeFrom(crc);
      if (type == 'IEND') {
        break;
      }
    }
    if (!written) {
      throw const FormatException('the PNG has no image data');
    }
  }

  static Future<String?> _pngXmp(RandomAccessFile reader) async {
    await reader.setPosition(0);
    final Uint8List signature = await reader.read(8);
    if (!_isPng(signature)) {
      return null;
    }
    int traversed = 0;
    while (true) {
      final Uint8List header = await reader.read(8);
      if (header.length < 8) {
        return null;
      }
      final int length = _u32(header, 0);
      final String type = String.fromCharCodes(header.sublist(4, 8));
      if (length > _maxHeader || traversed > _maxHeader) {
        return null;
      }
      traversed += 12 + length;
      if (type == 'iTXt' && length <= _maxXmp) {
        final Uint8List data = await reader.read(length);
        final String? packet = _itxtPacket(data);
        if (packet != null) {
          return packet;
        }
        await reader.read(4);
        continue;
      }
      if (type == 'IDAT' || type == 'IEND') {
        return null;
      }
      await reader.setPosition(await reader.position() + length + 4);
    }
  }

  static Future<ScannedPrint?> _readJpeg(RandomAccessFile reader) async {
    await reader.setPosition(0);
    final Uint8List soi = await reader.read(2);
    if (!_isJpeg(soi)) {
      return null;
    }
    Size? pixels;
    PrintMeta? meta;
    int traversed = 0;
    while (true) {
      final int? marker = await _jpegMarker(reader);
      if (marker == null) {
        break;
      }
      if (marker == 0xd9) {
        break;
      }
      if (marker == 0xda) {
        break;
      }
      if (_standalone(marker)) {
        continue;
      }
      final Uint8List lengthBytes = await reader.read(2);
      if (lengthBytes.length < 2) {
        break;
      }
      final int length = (lengthBytes[0] << 8) | lengthBytes[1];
      if (length < 2 || length > _maxHeader) {
        break;
      }
      final int dataLength = length - 2;
      traversed += 2 + length;
      if (traversed > _maxHeader) {
        break;
      }
      if (_sof(marker)) {
        final Uint8List data = await reader.read(dataLength);
        if (data.length >= 5) {
          final int height = (data[1] << 8) | data[2];
          final int width = (data[3] << 8) | data[4];
          if (width > 0 && height > 0) {
            pixels = Size(width.toDouble(), height.toDouble());
          }
        }
      } else if (marker == 0xe1 && dataLength <= _maxXmp) {
        final Uint8List data = await reader.read(dataLength);
        final String? packet = _jpegXmp(data);
        if (packet != null) {
          meta = PrintXmp.decode(packet);
        }
      } else {
        await reader.setPosition(await reader.position() + dataLength);
      }
    }
    if (pixels == null) {
      return null;
    }
    return ScannedPrint(
      format: PrintImageFormat.jpeg,
      pixels: pixels,
      meta: meta,
    );
  }

  static Future<void> _writeJpeg(
    RandomAccessFile input,
    RandomAccessFile output,
    PrintMeta meta,
  ) async {
    final String? existing = await _jpegXmpFile(input);
    final String packet = existing == null
        ? PrintXmp.encode(meta)
        : PrintXmp.merge(existing, meta);
    final Uint8List payload = Uint8List.fromList(<int>[
      ...utf8.encode(_jpegXmpPrefix),
      0,
      ...utf8.encode(packet),
    ]);
    final Uint8List segment = Uint8List.fromList(<int>[
      0xff,
      0xe1,
      ((payload.length + 2) >> 8) & 0xff,
      (payload.length + 2) & 0xff,
      ...payload,
    ]);

    await input.setPosition(0);
    await output.writeFrom(await input.read(2));
    bool written = false;
    bool first = true;
    while (true) {
      final int? marker = await _jpegMarker(input);
      if (marker == null) {
        break;
      }
      if (marker == 0xda) {
        if (!written) {
          await output.writeFrom(segment);
          written = true;
        }
        await output.writeFrom(<int>[0xff, marker]);
        await _copy(input, output, -1);
        break;
      }
      if (marker == 0xd9) {
        if (!written) {
          await output.writeFrom(segment);
          written = true;
        }
        await output.writeFrom(<int>[0xff, marker]);
        break;
      }
      if (_standalone(marker)) {
        await output.writeFrom(<int>[0xff, marker]);
        continue;
      }
      final Uint8List lengthBytes = await input.read(2);
      if (lengthBytes.length < 2) {
        break;
      }
      final int length = (lengthBytes[0] << 8) | lengthBytes[1];
      if (length < 2) {
        throw const FormatException('a JPEG segment has no length');
      }
      final int dataLength = length - 2;
      final bool isApp0 = marker == 0xe0;
      final bool isXmp = marker == 0xe1 && dataLength <= _maxXmp;
      Uint8List? data;
      if (isXmp) {
        data = await input.read(dataLength);
        if (_jpegXmp(data) != null) {
          continue;
        }
      }
      if (!written && !isApp0) {
        await output.writeFrom(segment);
        written = true;
      }
      await output.writeFrom(<int>[0xff, marker]);
      await output.writeFrom(lengthBytes);
      if (data != null) {
        await output.writeFrom(data);
      } else {
        await _copy(input, output, dataLength);
      }
      if (!written && isApp0) {
        await output.writeFrom(segment);
        written = true;
      }
      first = false;
    }
    if (!written) {
      throw const FormatException('the JPEG has no image data');
    }
    if (first) {
      throw const FormatException('the JPEG has no segments');
    }
  }

  static Future<String?> _jpegXmpFile(RandomAccessFile reader) async {
    await reader.setPosition(0);
    final Uint8List soi = await reader.read(2);
    if (!_isJpeg(soi)) {
      return null;
    }
    int traversed = 0;
    while (true) {
      final int? marker = await _jpegMarker(reader);
      if (marker == null || marker == 0xda || marker == 0xd9) {
        return null;
      }
      if (_standalone(marker)) {
        continue;
      }
      final Uint8List lengthBytes = await reader.read(2);
      if (lengthBytes.length < 2) {
        return null;
      }
      final int length = (lengthBytes[0] << 8) | lengthBytes[1];
      if (length < 2 || length > _maxHeader) {
        return null;
      }
      final int dataLength = length - 2;
      traversed += 2 + length;
      if (traversed > _maxHeader) {
        return null;
      }
      if (marker == 0xe1 && dataLength <= _maxXmp) {
        final Uint8List data = await reader.read(dataLength);
        final String? packet = _jpegXmp(data);
        if (packet != null) {
          return packet;
        }
      } else {
        await reader.setPosition(await reader.position() + dataLength);
      }
    }
  }

  /// Read the next marker, skipping the fill bytes between segments.
  static Future<int?> _jpegMarker(RandomAccessFile reader) async {
    int? byte;
    while (true) {
      final Uint8List next = await reader.read(1);
      if (next.isEmpty) {
        return null;
      }
      byte = next[0];
      if (byte != 0xff) {
        return null;
      }
      do {
        final Uint8List marker = await reader.read(1);
        if (marker.isEmpty) {
          return null;
        }
        byte = marker[0];
      } while (byte == 0xff);
      if (byte != 0x00) {
        return byte;
      }
      // 0xFF 0x00 is stuffed entropy data; not a marker.
    }
  }

  static bool _standalone(int marker) =>
      marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7);

  static bool _sof(int marker) =>
      marker == 0xc0 ||
      marker == 0xc1 ||
      marker == 0xc2 ||
      marker == 0xc3 ||
      marker == 0xc5 ||
      marker == 0xc6 ||
      marker == 0xc7 ||
      marker == 0xc9 ||
      marker == 0xca ||
      marker == 0xcb ||
      marker == 0xcd ||
      marker == 0xce ||
      marker == 0xcf;

  static Uint8List _itxtData(String packet) {
    final List<int> bytes = <int>[
      ...utf8.encode(_pngXmpKeyword),
      0,
      0,
      0,
      0,
      0,
      ...utf8.encode(packet),
    ];
    return Uint8List.fromList(bytes);
  }

  static String? _itxtPacket(Uint8List data) {
    final int keywordEnd = data.indexOf(0);
    if (keywordEnd < 0) {
      return null;
    }
    final String keyword = String.fromCharCodes(data.sublist(0, keywordEnd));
    if (keyword != _pngXmpKeyword) {
      return null;
    }
    int at = keywordEnd + 1;
    if (at + 2 > data.length) {
      return null;
    }
    final int compression = data[at++];
    final int method = data[at++];
    final int languageEnd = data.indexOf(0, at);
    if (languageEnd < 0) {
      return null;
    }
    at = languageEnd + 1;
    final int translatedEnd = data.indexOf(0, at);
    if (translatedEnd < 0) {
      return null;
    }
    at = translatedEnd + 1;
    final Uint8List text = Uint8List.sublistView(data, at);
    try {
      if (compression == 0) {
        return utf8.decode(text);
      }
      if (compression == 1 && method == 0) {
        return utf8.decode(ZLibDecoder().convert(text));
      }
    } on Object {
      return null;
    }
    return null;
  }

  static String? _jpegXmp(Uint8List data) {
    final List<int> prefix = <int>[...utf8.encode(_jpegXmpPrefix), 0];
    if (data.length <= prefix.length) {
      return null;
    }
    for (int i = 0; i < prefix.length; i++) {
      if (data[i] != prefix[i]) {
        return null;
      }
    }
    try {
      return utf8.decode(Uint8List.sublistView(data, prefix.length));
    } on FormatException {
      return null;
    }
  }

  static Uint8List _chunk(String type, Uint8List data) {
    final Uint8List typeBytes = Uint8List.fromList(type.codeUnits);
    final int crc = _pngCrc(type, data);
    return Uint8List.fromList(<int>[
      ..._u32Bytes(data.length),
      ...typeBytes,
      ...data,
      ..._u32Bytes(crc),
    ]);
  }

  static int _pngCrc(String type, Uint8List data) {
    final Uint8List all = Uint8List.fromList(<int>[...type.codeUnits, ...data]);
    int crc = 0xffffffff;
    for (final int byte in all) {
      crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >> 8);
    }
    return crc ^ 0xffffffff;
  }

  static final Uint32List _crcTable = _makeCrcTable();

  static Uint32List _makeCrcTable() {
    final Uint32List table = Uint32List(256);
    for (int n = 0; n < 256; n++) {
      int c = n;
      for (int k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
      }
      table[n] = c;
    }
    return table;
  }

  static int _u32(Uint8List bytes, int at) =>
      (bytes[at] << 24) |
      (bytes[at + 1] << 16) |
      (bytes[at + 2] << 8) |
      bytes[at + 3];

  static Uint8List _u32Bytes(int value) => Uint8List.fromList(<int>[
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ]);

  static Future<void> _copy(
    RandomAccessFile input,
    RandomAccessFile output,
    int length,
  ) async {
    int remaining = length;
    while (length < 0 || remaining > 0) {
      final int ask = length < 0
          ? 64 * 1024
          : (remaining < 64 * 1024 ? remaining : 64 * 1024);
      final Uint8List bytes = await input.read(ask);
      if (bytes.isEmpty) {
        if (length < 0) {
          return;
        }
        throw const FormatException('a file ended before its length');
      }
      await output.writeFrom(bytes);
      if (length < 0) {
        continue;
      }
      remaining -= bytes.length;
    }
  }
}
