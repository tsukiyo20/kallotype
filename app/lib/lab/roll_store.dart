import 'dart:convert';
import 'dart:io';

import 'image_file.dart';
import 'roll.dart';
import 'settings.dart';

/// The roll being carried, on disk.
///
/// A roll is not an export: it is the work in progress, so it lives in the
/// app's own folder beside the settings, and its frames are the PNGs the model
/// wrote there. A JSON holds what a PNG cannot say about itself — when each
/// frame went into the developer, and where the photograph came from.
abstract final class RollStore {
  static const String _record = 'roll.json';

  /// Where the roll lives. Null when the app has nowhere of its own to write.
  static Directory? get folder {
    final Directory? base = Settings.directory;
    return base == null
        ? null
        : Directory('${base.path}${Platform.pathSeparator}roll');
  }

  /// The file a frame's print is written to: `01.png`, `02.png`, in the roll's
  /// own order, so that the model writes into the roll rather than beside it.
  static File frameFile(Directory folder, int number) => File(
        '${folder.path}${Platform.pathSeparator}'
        '${number.toString().padLeft(2, '0')}.png',
      );

  static Future<void> save(Roll roll, {Directory? folder}) async {
    final Directory? target = folder ?? RollStore.folder;
    if (target == null) {
      return;
    }
    await target.create(recursive: true);
    final Map<String, Object?> record = <String, Object?>{
      'number': roll.number,
      'stock': roll.stockId,
      'label': roll.stockLabel,
      if (roll.paperId != null) 'paper': roll.paperId,
      if (roll.paperLabel != null) 'paper_label': roll.paperLabel,
      if (roll.spectral) 'spectral': true,
      if (roll.photo != null) 'photo': roll.photo,
      'frames': <Object?>[
        for (final Frame frame in roll.frames)
          <String, Object?>{
            'number': frame.number,
            'minutes': frame.minutes,
            'temp_c': frame.tempC,
          },
      ],
    };
    await File('${target.path}${Platform.pathSeparator}$_record')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(record));
  }

  /// Read the roll back, with its frames decoded at the bench's width.
  ///
  /// A frame whose PNG has gone is a frame that is not on the roll: the record
  /// is the roll's memory, not its contents.
  static Future<Roll?> load({Directory? folder, int width = 1200}) async {
    final Directory? target = folder ?? RollStore.folder;
    if (target == null) {
      return null;
    }
    final File record =
        File('${target.path}${Platform.pathSeparator}$_record');
    if (!record.existsSync()) {
      return null;
    }
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(await record.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
    final List<Frame> frames = <Frame>[];
    for (final Object? entry in json['frames'] as List<Object?>? ?? const <Object?>[]) {
      final Map<String, dynamic> frame = entry! as Map<String, dynamic>;
      final int number = (frame['number'] as num).toInt();
      final File image = frameFile(target, number);
      if (!image.existsSync()) {
        continue;
      }
      frames.add(
        Frame(
          number: number,
          minutes: (frame['minutes'] as num).toDouble(),
          tempC: (frame['temp_c'] as num).toDouble(),
          image: await decode(image, width: width),
        ),
      );
    }
    if (frames.isEmpty) {
      return null;
    }
    return Roll(
      number: (json['number'] as num?)?.toInt() ?? 1,
      stockId: json['stock'] as String? ?? '',
      stockLabel: json['label'] as String? ?? '',
      paperId: json['paper'] as String?,
      paperLabel: json['paper_label'] as String?,
      spectral: json['spectral'] == true,
      photo: json['photo'] as String?,
      frames: frames,
    );
  }
}
