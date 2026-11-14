import 'package:xml/xml.dart';

import 'print.dart';
import 'print_meta.dart';
import 'stock.dart';

/// The XMP namespaces a Kallo record uses.
const String kalloMetaNamespace = 'adobe:ns:meta/';
const String kalloRdfNamespace = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
const String kalloDcNamespace = 'http://purl.org/dc/elements/1.1/';
const String kalloXmpNamespace = 'http://ns.adobe.com/xap/1.0/';
const String kalloRecordNamespace = 'https://kallo.app/ns/1.0/';

/// The XMP packet a print carries.
///
/// This is deliberately a standard packet with one private namespace. The
/// standard fields (`dc:title`, `xmp:CreatorTool`, `xmp:CreateDate`) are what
/// other software may preserve; the `kallo:` fields are the record this app
/// needs. A reader must find the record by namespace, not by the presence of
/// any XMP: a file may already have XMP from a camera or an editor.
abstract final class PrintXmp {
  static const String _creatorTool = 'Kallo';

  /// Encode one record as a complete XMP packet.
  static String encode(PrintMeta meta) {
    final XmlBuilder builder = XmlBuilder();
    builder.processing(
      'xpacket',
      'begin="\uFEFF" id="W5M0MpCehiHzreSzNTczkc9d"',
    );
    builder.element(
      'x:xmpmeta',
      attributes: <String, String>{'xmlns:x': kalloMetaNamespace},
      nest: () {
        builder.element(
          'rdf:RDF',
          attributes: <String, String>{'xmlns:rdf': kalloRdfNamespace},
          nest: () {
            builder.element(
              'rdf:Description',
              attributes: <String, String>{
                'rdf:about': '',
                'xmlns:dc': kalloDcNamespace,
                'xmlns:xmp': kalloXmpNamespace,
                'xmlns:kallo': kalloRecordNamespace,
                'xmp:CreatorTool': _creatorTool,
                'xmp:CreateDate': _date(meta.printed),
                'xmp:MetadataDate': _date(meta.updated),
                'kallo:schema': '${meta.schema}',
                'kallo:id': meta.id,
                'kallo:kind': meta.kind.name,
                'kallo:printed': _date(meta.printed),
                'kallo:added': _date(meta.added),
                'kallo:updated': _date(meta.updated),
                'kallo:printNumber': '${meta.printNumber}',
                if (meta.process != null) 'kallo:process': meta.process!.name,
                if (meta.film != null) 'kallo:film': meta.film!,
                if (meta.paper != null) 'kallo:paper': meta.paper!,
                if (meta.minutes != null)
                  'kallo:minutes': _number(meta.minutes!),
                if (meta.tempC != null) 'kallo:tempC': _number(meta.tempC!),
                if (meta.sourceName != null)
                  'kallo:sourceName': meta.sourceName!,
              },
              nest: () {
                builder.element(
                  'dc:title',
                  nest: () {
                    builder.element(
                      'rdf:Alt',
                      nest: () {
                        builder.element(
                          'rdf:li',
                          attributes: <String, String>{'xml:lang': 'x-default'},
                          nest: meta.title,
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
    builder.processing('xpacket', 'end="w"');
    return builder.buildDocument().toXmlString();
  }

  /// Read a Kallo record from an XMP packet, or null when the packet is not a
  /// Kallo record.
  ///
  /// The reader is intentionally forgiving about dates and numbers: a marker
  /// written by a future version should still produce a print, not an exception
  /// in the middle of a folder scan. It is strict about the namespace and the
  /// id, because those are what make it a Kallo print at all.
  static PrintMeta? decode(String packet) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(packet);
    } on XmlException {
      return null;
    }

    final XmlElement? description = document
        .findAllElements('Description', namespaceUri: kalloRdfNamespace)
        .where(_isKalloDescription)
        .firstOrNull;
    if (description == null) {
      return null;
    }

    final String? id = _value(description, 'id');
    if (id == null || id.isEmpty) {
      return null;
    }

    final String? title = _title(description);
    final String? film = _value(description, 'film');
    final String? processName = _value(description, 'process');
    final FilmProcess? process = switch (processName) {
      'negative' => FilmProcess.negative,
      'reversal' => FilmProcess.reversal,
      'monochrome' => FilmProcess.monochrome,
      _ => filmProcessFromName(film),
    };

    final DateTime now = DateTime.now().toUtc();
    final DateTime printed =
        _dateValue(_value(description, 'printed')) ??
        _dateValue(_value(description, 'added')) ??
        _dateValue(_value(description, 'updated')) ??
        now;
    final DateTime added = _dateValue(_value(description, 'added')) ?? printed;
    final DateTime updated =
        _dateValue(_value(description, 'updated')) ?? added;

    return PrintMeta(
      id: id,
      schema: int.tryParse(_value(description, 'schema') ?? '') ?? 1,
      kind: PrintKind.parse(_value(description, 'kind')),
      title: title ?? '',
      printed: printed,
      added: added,
      updated: updated,
      printNumber: int.tryParse(_value(description, 'printNumber') ?? '') ?? 1,
      process: process,
      film: film,
      paper: _value(description, 'paper'),
      minutes: _doubleValue(_value(description, 'minutes')),
      tempC: _doubleValue(_value(description, 'tempC')),
      sourceName: _value(description, 'sourceName'),
    );
  }

  /// Whether a packet contains a Kallo record. Used by scans before parsing the
  /// record twice.
  static bool looksLikeKallo(String packet) {
    try {
      return XmlDocument.parse(packet)
          .findAllElements('Description', namespaceUri: kalloRdfNamespace)
          .where(_isKalloDescription)
          .isNotEmpty;
    } on XmlException {
      return false;
    }
  }

  /// Replace only the Kallo description in [existing], preserving every other
  /// namespace and packet the file already had.
  ///
  /// An XMP packet that cannot be parsed is not overwritten: a camera or an
  /// editor may have written it, and losing their metadata to gain ours is not
  /// a trade this app makes.
  static String merge(String existing, PrintMeta meta) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(existing);
    } on XmlException catch (error) {
      throw FormatException('the existing XMP is not readable: $error');
    }

    final XmlElement? rdf = document
        .findAllElements('RDF', namespaceUri: kalloRdfNamespace)
        .firstOrNull;
    if (rdf == null) {
      throw const FormatException('the existing XMP has no rdf:RDF');
    }

    for (final XmlElement description
        in rdf
            .findElements('Description', namespaceUri: kalloRdfNamespace)
            .where(_isKalloDescription)
            .toList()) {
      description.parent?.children.remove(description);
    }

    final XmlDocument fresh = XmlDocument.parse(encode(meta));
    final XmlElement? replacement = fresh
        .findAllElements('Description', namespaceUri: kalloRdfNamespace)
        .where(_isKalloDescription)
        .firstOrNull;
    if (replacement == null) {
      throw const FormatException('the new XMP has no description');
    }
    rdf.children.add(replacement.copy());
    return document.toXmlString();
  }

  static bool _isKalloDescription(XmlElement element) =>
      _value(element, 'schema') != null || _value(element, 'id') != null;

  static String? _value(XmlElement description, String local) {
    final String? attribute = description.getAttribute(
      local,
      namespaceUri: kalloRecordNamespace,
    );
    if (attribute != null) {
      return attribute;
    }
    // A future writer may choose elements instead of attributes. Reading both
    // costs one query and keeps the marker forward-compatible.
    final XmlElement? element = description
        .findElements(local, namespaceUri: kalloRecordNamespace)
        .firstOrNull;
    return element?.innerText.trim();
  }

  static String? _title(XmlElement description) {
    final XmlElement? title = description
        .findElements('title', namespaceUri: kalloDcNamespace)
        .firstOrNull;
    if (title == null) {
      return null;
    }
    final Iterable<XmlElement> alternatives = title.findAllElements(
      'li',
      namespaceUri: kalloRdfNamespace,
    );
    final String? preferred = alternatives
        .where(
          (XmlElement element) =>
              element.getAttribute('lang', namespaceUri: '*') == 'x-default',
        )
        .firstOrNull
        ?.innerText
        .trim();
    if (preferred != null && preferred.isNotEmpty) {
      return preferred;
    }
    final String? first = alternatives.firstOrNull?.innerText.trim();
    return first == null || first.isEmpty ? null : first;
  }

  static DateTime? _dateValue(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  static double? _doubleValue(String? value) =>
      value == null ? null : double.tryParse(value);

  static String _date(DateTime date) => date.toUtc().toIso8601String();

  static String _number(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
