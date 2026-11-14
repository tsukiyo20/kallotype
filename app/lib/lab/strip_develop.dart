import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'chart.dart';
import 'image_file.dart';
import 'model.dart';
import 'stock.dart';
import 'strip.dart';
import 'strip_store.dart';

/// The width a print on the strip is rendered at.
///
/// The strip is a bench instrument, and the model's grain belongs to the
/// sampling: a print rendered here is a print at this size, not a larger one
/// scaled down. A final print is rendered again from the photograph.
const int stripWidth = 1200;

/// The largest a final print is asked for.
const int printWidth = 6000;

/// Develop one print onto the strip.
///
/// The first print fixes the strip's enlarger balance; every later print reuses
/// it, so what changes between the prints is the development and not the timer.
/// The chart is read from the same stock and time — it is a fact about the
/// film, not about this photograph.
Future<TestStrip> developTestPrint({
  required Model model,
  required TestStrip strip,
  required double minutes,
  Directory? folder,
  int width = stripWidth,
}) async {
  final String? photo = strip.photo;
  if (photo == null) {
    throw const FileSystemException('a test strip needs a photograph');
  }
  final File photograph = File(photo);
  if (!photograph.existsSync()) {
    throw FileSystemException('the photograph is gone', photo);
  }
  if (!(minutes.isFinite && minutes > 0)) {
    throw ArgumentError.value(minutes, 'minutes', 'a development is positive');
  }
  final Directory target = folder ?? StripStore.folderOrThrow;
  await target.create(recursive: true);
  final File output = StripStore.printFile(target, minutes);

  await model.develop(
    photograph: photograph,
    stock: strip.stockId,
    paper: strip.paperId ?? Stocks.paper,
    minutes: minutes,
    tempC: strip.tempC,
    width: width,
    output: output,
    spectral: strip.spectral,
    balanceFrom: strip.balanceFrom,
  );

  FilmChart? chart;
  try {
    final List<FilmChart>? charts = await model.chart(
      stock: strip.stockId,
      times: <double>[minutes],
      tempC: strip.tempC,
    );
    chart = charts == null || charts.isEmpty ? null : charts.first;
  } on Object catch (error) {
    // A print without its chart is still a print; the panel says so.
    Model.log('the strip could not be charted: $error');
  }

  final TestStrip next = strip.withPrint(
    TestPrint(
      minutes: minutes,
      tempC: strip.tempC,
      image: await decode(output, width: width),
      chart: chart,
      file: output,
    ),
  );
  await StripStore.save(next, folder: target);
  return next;
}

/// The print a test strip would make at this development, at bench size.
///
/// It is the strip's exposure, not the print's: the preview and the print that
/// will replace it at the same time are made the same way. The file is a
/// preview and overwrites itself; it is not part of the strip.
Future<ui.Image> previewTestPrint({
  required Model model,
  required TestStrip strip,
  required double minutes,
  Directory? folder,
  int width = 760,
}) async {
  final String? photo = strip.photo;
  if (photo == null) {
    throw const FileSystemException('a test strip needs a photograph');
  }
  final Directory target = folder ?? StripStore.folderOrThrow;
  await target.create(recursive: true);
  final File output = File(
    '${target.path}${Platform.pathSeparator}strip-preview.png',
  );
  await model.develop(
    photograph: File(photo),
    stock: strip.stockId,
    paper: strip.paperId ?? Stocks.paper,
    minutes: minutes,
    tempC: strip.tempC,
    width: width,
    output: output,
    spectral: strip.spectral,
    balanceFrom: strip.balanceFrom,
  );
  return decode(output, width: width);
}

/// The finished print a darkroom would make at this development, at bench
/// size. Balanced for this negative, with the filters and the glass.
Future<ui.Image> previewFinalPrint({
  required Model model,
  required TestStrip strip,
  required double minutes,
  double printEv = 0,
  String filters = '',
  String? heatGlass,
  Directory? folder,
  int width = 760,
}) async {
  final String? photo = strip.photo;
  if (photo == null) {
    throw const FileSystemException('a print needs a photograph');
  }
  final Directory target = folder ?? StripStore.folderOrThrow;
  await target.create(recursive: true);
  final File output = File(
    '${target.path}${Platform.pathSeparator}strip-print-preview.png',
  );
  await model.develop(
    photograph: File(photo),
    stock: strip.stockId,
    paper: strip.paperId ?? Stocks.paper,
    minutes: minutes,
    tempC: strip.tempC,
    width: width,
    output: output,
    spectral: strip.spectral,
    printEv: printEv,
    filters: filters,
    heatGlass: heatGlass,
  );
  return decode(output, width: width);
}

/// Print the chosen development as a finished print, balanced on its own.
///
/// A test strip is one exposure; a finished print is the enlarger dialled for
/// this negative. That is why it is rendered again, at the size the photograph
/// has, and why it is not a copy of the strip's print.
Future<File> printTest({
  required Model model,
  required TestStrip strip,
  required double minutes,
  required Directory exports,
  required String paperName,
  String? filmName,
  int? frame,
  double printEv = 0,
  String filters = '',
  String? heatGlass,
  int width = printWidth,
}) async {
  final String? photo = strip.photo;
  if (photo == null) {
    throw const FileSystemException('a print needs a photograph');
  }
  final File photograph = File(photo);
  if (!photograph.existsSync()) {
    throw FileSystemException('the photograph is gone', photo);
  }
  await exports.create(recursive: true);
  final int own = await _width(photograph);
  final int asked = own > 0 ? math.min(own, width) : width;
  final String stem =
      'print-${minutes.toStringAsFixed(1).replaceAll('.', '-')}min';
  final File output = File('${exports.path}${Platform.pathSeparator}$stem.png');
  await model.develop(
    photograph: photograph,
    stock: strip.stockId,
    paper: strip.paperId ?? Stocks.paper,
    minutes: minutes,
    tempC: strip.tempC,
    width: asked,
    output: output,
    spectral: strip.spectral,
    printEv: printEv,
    filters: filters,
    heatGlass: heatGlass,
  );
  final File record = File(
    '${exports.path}${Platform.pathSeparator}$stem.json',
  );
  await record.writeAsString(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'frame': ?frame,
      'film': filmName ?? strip.stockLabel,
      'paper': paperName,
      'minutes': minutes,
      'temp_c': strip.tempC,
      'print_ev': printEv,
      'filters': filters,
      'heat_glass': heatGlass,
    }),
  );
  return output;
}

/// A file's width, read from its header rather than by decoding it.
Future<int> _width(File file) async {
  final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
    await file.readAsBytes(),
  );
  final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(
    buffer,
  );
  final int width = descriptor.width;
  descriptor.dispose();
  buffer.dispose();
  return width;
}
