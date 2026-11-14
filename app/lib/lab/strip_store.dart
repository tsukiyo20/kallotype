import 'dart:convert';
import 'dart:io';

import 'chart.dart';
import 'image_file.dart';
import 'roll_store.dart';
import 'strip.dart';

/// The test strip being made, on disk.
///
/// A strip is the work in progress, not an export: it lives in the app's own
/// folder beside the settings, and its prints are the PNGs the model wrote. A
/// JSON says what a PNG cannot — the development, the strip's one exposure, and
/// the densitometer's reading at each time.
abstract final class StripStore {
  static const String _record = 'strip.json';

  /// Where the strip lives. The same folder the old roll used, because it is
  /// the same darkroom and the photograph is already there.
  static Directory? get folder => RollStore.folder;

  /// The file a print is written to. A print is named by its development, so
  /// re-developing the same time replaces the print rather than growing a
  /// second one at the same place on the strip.
  static File printFile(Directory folder, double minutes) => File(
    '${folder.path}${Platform.pathSeparator}'
    'strip-${minutes.toStringAsFixed(2)}.png',
  );

  /// Copy the photograph into the strip's folder.
  ///
  /// A file panel can hand over a temporary copy of something in a photo
  /// library; a strip that pointed at a file that will be gone tomorrow could
  /// not be developed again. The name is kept: the photograph is the one thing
  /// here the app did not make.
  static Future<File> keep(File photograph, {Directory? folder}) async {
    final Directory target = folder ?? folderOrThrow;
    await target.create(recursive: true);
    final String name = photograph.path.split(Platform.pathSeparator).last;
    final File kept = File('${target.path}${Platform.pathSeparator}$name');
    if (kept.absolute.path == photograph.absolute.path) {
      return kept;
    }
    return photograph.copy(kept.path);
  }

  static Directory get folderOrThrow {
    final Directory? target = folder;
    if (target == null) {
      throw const FileSystemException(
        'the app has no folder to write a strip to',
      );
    }
    return target;
  }

  static Future<void> save(TestStrip strip, {Directory? folder}) async {
    final Directory? target = folder ?? StripStore.folder;
    if (target == null) {
      return;
    }
    await target.create(recursive: true);
    final Map<String, Object?> record = <String, Object?>{
      if (strip.photo != null) 'photo': strip.photo,
      'stock': strip.stockId,
      'label': strip.stockLabel,
      if (strip.paperId != null) 'paper': strip.paperId,
      if (strip.paperLabel != null) 'paper_label': strip.paperLabel,
      if (strip.spectral) 'spectral': true,
      'temp_c': strip.tempC,
      if (strip.balanceFrom != null) 'balance_from': strip.balanceFrom,
      'prints': <Object?>[
        for (final TestPrint print in strip.prints)
          <String, Object?>{
            'minutes': print.minutes,
            'temp_c': print.tempC,
            'image': (print.file ?? printFile(target, print.minutes)).path
                .split(Platform.pathSeparator)
                .last,
            if (print.chart != null) ...<String, Object?>{
              'gamma': print.chart!.gamma,
              'd_min': print.chart!.dMin,
              'd_max': print.chart!.dMax,
              'patches': print.chart!.patches,
              'log_e': print.chart!.logE,
            },
          },
      ],
    };
    await File('${target.path}${Platform.pathSeparator}$_record')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(record));
  }

  /// Read the strip back, with its prints decoded at [width].
  ///
  /// A print whose PNG has gone is not on the strip: the record is the strip's
  /// memory, not its contents. A photograph with no prints is still worth
  /// loading — it is the frame the next print will be made from.
  static Future<TestStrip?> load({Directory? folder, int width = 1200}) async {
    final Directory? target = folder ?? StripStore.folder;
    if (target == null) {
      return null;
    }
    final File record = File('${target.path}${Platform.pathSeparator}$_record');
    if (!record.existsSync()) {
      return null;
    }
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(await record.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
    final List<TestPrint> prints = <TestPrint>[];
    for (final Object? entry
        in json['prints'] as List<Object?>? ?? const <Object?>[]) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final String? imageName = entry['image'] as String?;
      final File image = imageName == null
          ? printFile(target, (entry['minutes'] as num?)?.toDouble() ?? 0)
          : File('${target.path}${Platform.pathSeparator}$imageName');
      final double minutes = (entry['minutes'] as num?)?.toDouble() ?? 0;
      if (minutes <= 0 || !image.existsSync()) {
        continue;
      }
      final List<double>? gamma = _numbers(entry['gamma']);
      final List<double>? dMin = _numbers(entry['d_min']);
      final List<double>? dMax = _numbers(entry['d_max']);
      final List<List<double>>? patches = _patches(entry['patches']);
      final List<double>? logE = _numbers(entry['log_e']);
      final FilmChart? chart =
          gamma != null &&
              dMin != null &&
              dMax != null &&
              patches != null &&
              logE != null
          ? FilmChart(
              minutes: minutes,
              tempC: (entry['temp_c'] as num?)?.toDouble() ?? 20,
              gamma: gamma,
              dMin: dMin,
              dMax: dMax,
              patches: patches,
              logE: logE,
            )
          : null;
      prints.add(
        TestPrint(
          minutes: minutes,
          tempC: (entry['temp_c'] as num?)?.toDouble() ?? 20,
          image: await decode(image, width: width),
          chart: chart,
          file: image,
        ),
      );
    }
    final String? photo = json['photo'] as String?;
    if (photo == null && prints.isEmpty) {
      return null;
    }
    return TestStrip(
      photo: photo,
      stockId: json['stock'] as String? ?? '',
      stockLabel: json['label'] as String? ?? '',
      paperId: json['paper'] as String?,
      paperLabel: json['paper_label'] as String?,
      spectral: json['spectral'] == true,
      tempC: (json['temp_c'] as num?)?.toDouble() ?? 20,
      balanceFrom: (json['balance_from'] as num?)?.toDouble(),
      prints: prints,
    );
  }

  /// Forget the strip: its record and its prints. The photograph stays, because
  /// it is not the strip's — it was the person's.
  static Future<void> clear({Directory? folder}) async {
    final Directory? target = folder ?? StripStore.folder;
    if (target == null) {
      return;
    }
    final File record = File('${target.path}${Platform.pathSeparator}$_record');
    if (record.existsSync()) {
      await record.delete();
    }
    for (final FileSystemEntity entity in target.listSync()) {
      if (entity is File &&
          entity.path.split(Platform.pathSeparator).last.startsWith('strip-')) {
        await entity.delete();
      }
    }
  }
}

List<double>? _numbers(Object? value) => value == null
    ? null
    : <double>[
        for (final Object? number in (value as List<Object?>))
          (number! as num).toDouble(),
      ];

List<List<double>>? _patches(Object? value) => value == null
    ? null
    : <List<double>>[
        for (final Object? patch in (value as List<Object?>))
          <double>[
            for (final Object? number in (patch! as List<Object?>))
              (number! as num).toDouble(),
          ],
      ];
