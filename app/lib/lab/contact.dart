import 'dart:convert';
import 'dart:io' as io;
import 'dart:ui' as ui;

import 'image_file.dart';

/// The proof on the table: one sheet of paper, exposed once, and where its
/// frames are.
///
/// The image is the model's — a contact print of the whole ladder on the roll's
/// own paper — and the rects come from the record the model wrote beside it. A
/// viewer that guessed the layout would be a second model, and the table's
/// claim is that it is the first one's print.
class ContactProof {
  const ContactProof({
    required this.image,
    required this.pixels,
    required this.frames,
    required this.paperMargin,
    this.file,
  });

  /// The sheet, decoded at the wall's width rather than the file's.
  final ui.Image image;

  /// The decoded image's size, which is what the rects below are in.
  final ui.Size pixels;

  /// Where each frame is, in the decoded image's pixels.
  final List<ContactFrame> frames;

  /// The paper left around the strips, in the decoded image's pixels.
  final double paperMargin;

  /// The sheet on disk. Null for a proof a test built, which is the one case
  /// where a proof has pixels and no file to read them from.
  final io.File? file;

  /// The sheet at the size a loupe needs.
  ///
  /// The table holds the sheet at the width it is shown at; a loupe at three
  /// times that needs more than the table's copy, so it is read from the file
  /// the model wrote — the print, not a drawing of it. Null when there is no
  /// file, and the caller shows the table's copy instead.
  Future<ui.Image?> magnified({int width = 4000}) async {
    final io.File? file = this.file;
    if (file == null || !file.existsSync()) {
      return null;
    }
    return decode(file, width: width);
  }

  /// Read the proof the model wrote: `contact.png` and `contact.json`.
  ///
  /// Null when either is missing, because a proof that is not on disk is not a
  /// proof — the table falls back to the chart it can draw, and says so.
  static Future<ContactProof?> read(
    io.File sheet,
    io.File record, {
    int width = 2400,
  }) async {
    if (!sheet.existsSync() || !record.existsSync()) {
      return null;
    }
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(await record.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
    final double recorded = (json['width'] as num?)?.toDouble() ?? 0;
    if (recorded <= 0) {
      return null;
    }
    final ui.Image image = await decode(sheet, width: width);
    final double scale = image.width / recorded;
    final List<ContactFrame> frames = <ContactFrame>[
      for (final Object? entry
          in json['frames'] as List<Object?>? ?? const <Object?>[])
        if (entry is Map<String, dynamic>)
          ContactFrame(
            number: (entry['number'] as num?)?.toInt() ?? 0,
            minutes: (entry['minutes'] as num?)?.toDouble() ?? 0,
            rect: ui.Rect.fromLTWH(
              ((entry['x'] as num?)?.toDouble() ?? 0) * scale,
              ((entry['y'] as num?)?.toDouble() ?? 0) * scale,
              ((entry['width'] as num?)?.toDouble() ?? 0) * scale,
              ((entry['height'] as num?)?.toDouble() ?? 0) * scale,
            ),
          ),
    ];
    return ContactProof(
      image: image,
      pixels: ui.Size(image.width.toDouble(), image.height.toDouble()),
      frames: frames,
      paperMargin: ((json['margin'] as num?)?.toDouble() ?? 0) * scale,
      file: sheet,
    );
  }
}

/// One strip's image on the proof, and the development it was printed at.
class ContactFrame {
  const ContactFrame({
    required this.number,
    required this.minutes,
    required this.rect,
  });

  /// Which frame on the roll, from one.
  final int number;

  /// How long that strip was developed, in minutes.
  final double minutes;

  /// The image area, in the decoded sheet's pixels.
  final ui.Rect rect;
}
