import 'dart:io' as io;
import 'dart:ui' as ui;

import 'chart.dart';
import 'clock.dart';
import 'stock.dart';

/// One print on the test strip: one development, printed on the strip's own
/// exposure.
///
/// It is a print and not a preview: the model rendered it at the strip's width
/// and the enlarger was left where the first print set it. The chart beside it
/// is the densitometer's reading of the same strip, so the print and the curve
/// are two views of one development.
class TestPrint {
  const TestPrint({
    required this.minutes,
    required this.tempC,
    this.image,
    this.chart,
    this.file,
  });

  /// How long this print was in the developer.
  final double minutes;

  /// The developer's temperature.
  final double tempC;

  /// The print, decoded at the strip's width.
  final ui.Image? image;

  /// The densitometer's reading at this development, when the model measured
  /// one. Null when the model could not be asked — the app still has the print.
  final FilmChart? chart;

  /// The PNG the model wrote, when this print came off disk.
  final io.File? file;

  /// `3:00`, `12:30` — the clock a darkroom timer would show.
  String get clock => darkroomClock(minutes);

  bool get hasChart => chart != null;

  /// Density at each patch, averaged over the records: the curve's y values.
  List<double>? get toneCurve {
    final FilmChart? chart = this.chart;
    if (chart == null) {
      return null;
    }
    return <double>[
      for (final List<double> patch in chart.patches)
        (patch[0] + patch[1] + patch[2]) / 3,
    ];
  }

  TestPrint withImage(ui.Image image, {io.File? file}) => TestPrint(
    minutes: minutes,
    tempC: tempC,
    image: image,
    chart: chart,
    file: file,
  );

  TestPrint withChart(FilmChart chart) => TestPrint(
    minutes: minutes,
    tempC: tempC,
    image: image,
    chart: chart,
    file: file,
  );
}

/// The test strip: one photograph, one exposure, several developments.
///
/// A darkroom's test strip is one print at a time, each made with the enlarger
/// where the last one left it; the strip is what those prints are when they are
/// laid side by side. So the first print fixes the balance and every later one
/// reuses it — otherwise the prints are balanced one by one and the development
/// is no longer the only thing that changed.
class TestStrip {
  const TestStrip({
    this.photo,
    this.stockId = Stocks.defaultId,
    this.stockLabel = 'VISION3 500T',
    this.paperId = Stocks.paper,
    this.paperLabel = Stocks.paperShort,
    this.spectral = false,
    this.tempC = 20,
    this.balanceFrom,
    this.prints = const <TestPrint>[],
  });

  /// The photograph, copied into the strip's own folder when it was chosen.
  /// Null before anything has been chosen.
  final String? photo;

  final String stockId;
  final String stockLabel;

  final String? paperId;
  final String? paperLabel;

  /// Whether this strip was exposed through the spectrum.
  final bool spectral;

  /// The developer's temperature for every print.
  final double tempC;

  /// The development whose enlarger balance the whole strip shares: the first
  /// print's. Null until the first print is made.
  final double? balanceFrom;

  /// The prints, oldest development first. A print at a time already on the
  /// strip replaces it.
  final List<TestPrint> prints;

  /// What the strip is called: the photograph's own name.
  String? get name {
    final String? photo = this.photo;
    if (photo == null) {
      return null;
    }
    final String file = photo.split(io.Platform.pathSeparator).last;
    final int dot = file.lastIndexOf('.');
    return dot <= 0 ? file : file.substring(0, dot);
  }

  bool get hasPrints => prints.isNotEmpty;

  /// The print at a development, or the nearest one on the strip.
  TestPrint? printAt(double minutes) {
    if (prints.isEmpty) {
      return null;
    }
    TestPrint best = prints.first;
    double distance = (best.minutes - minutes).abs();
    for (final TestPrint print in prints.skip(1)) {
      final double next = (print.minutes - minutes).abs();
      if (next < distance) {
        best = print;
        distance = next;
      }
    }
    return best;
  }

  TestPrint? get latest => prints.isEmpty ? null : prints.last;

  /// The strip with one more print. The first print sets the balance; every
  /// later one is made on it.
  TestStrip withPrint(TestPrint print) {
    final List<TestPrint> next = <TestPrint>[
      for (final TestPrint existing in prints)
        if (existing.minutes != print.minutes) existing,
      print,
    ]..sort((TestPrint a, TestPrint b) => a.minutes.compareTo(b.minutes));
    return TestStrip(
      photo: photo,
      stockId: stockId,
      stockLabel: stockLabel,
      paperId: paperId,
      paperLabel: paperLabel,
      spectral: spectral,
      tempC: tempC,
      balanceFrom: balanceFrom ?? print.minutes,
      prints: next,
    );
  }

  TestStrip without(double minutes) {
    final List<TestPrint> next = <TestPrint>[
      for (final TestPrint print in prints)
        if (print.minutes != minutes) print,
    ];
    return TestStrip(
      photo: photo,
      stockId: stockId,
      stockLabel: stockLabel,
      paperId: paperId,
      paperLabel: paperLabel,
      spectral: spectral,
      tempC: tempC,
      balanceFrom: next.isEmpty ? null : balanceFrom,
      prints: next,
    );
  }

  /// Change the film or the paper: a strip is one material, so a new choice is
  /// a new strip. The photograph stays.
  TestStrip withMaterials({
    String? stockId,
    String? stockLabel,
    String? paperId,
    String? paperLabel,
  }) => TestStrip(
    photo: photo,
    stockId: stockId ?? this.stockId,
    stockLabel: stockLabel ?? this.stockLabel,
    paperId: paperId ?? this.paperId,
    paperLabel: paperLabel ?? this.paperLabel,
    spectral: spectral,
    tempC: tempC,
  );

  /// The same photograph and materials, with no prints: a new test strip.
  TestStrip withoutPrints() => TestStrip(
    photo: photo,
    stockId: stockId,
    stockLabel: stockLabel,
    paperId: paperId,
    paperLabel: paperLabel,
    spectral: spectral,
    tempC: tempC,
  );

  TestStrip withPhoto(String photo) => TestStrip(
    photo: photo,
    stockId: stockId,
    stockLabel: stockLabel,
    paperId: paperId,
    paperLabel: paperLabel,
    spectral: spectral,
    tempC: tempC,
  );

  TestStrip withTemperature(double tempC) => TestStrip(
    photo: photo,
    stockId: stockId,
    stockLabel: stockLabel,
    paperId: paperId,
    paperLabel: paperLabel,
    spectral: spectral,
    tempC: tempC,
    balanceFrom: balanceFrom,
    prints: prints,
  );
}
