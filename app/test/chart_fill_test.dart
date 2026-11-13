import 'package:flutter_test/flutter_test.dart';
import 'package:kallo_ui/lab/chart.dart';
import 'package:kallo_ui/lab/chart_fill.dart';
import 'package:kallo_ui/lab/model.dart';
import 'package:kallo_ui/lab/roll.dart';

/// A model that can chart, without a photograph or a library.
class _Charting extends ProcessModel {
  const _Charting(this.charts) : super('');

  final List<FilmChart>? charts;

  @override
  bool get available => true;

  @override
  Future<List<FilmChart>?> chart({
    required String stock,
    required List<double> times,
    required double tempC,
  }) async =>
      charts;
}

FilmChart _chart(double minutes) => FilmChart(
      minutes: minutes,
      tempC: 20,
      gamma: <double>[0.5, 0.5 + minutes / 100, 0.5],
      dMin: <double>[0.05, 0.05, 0.05],
      dMax: <double>[3.0, 3.0, 3.0],
      patches: <List<double>>[
        for (int i = 0; i < 9; i++) <double>[0.1 * i, 0.1 * i, 0.1 * i],
      ],
    );

Roll _roll() => Roll(
      stockId: 'vision3_500t',
      stockLabel: 'VISION3 500T',
      photo: '/photographs/uji.jpg',
      frames: const <Frame>[
        Frame(number: 1, minutes: 3, tempC: 20),
        Frame(number: 2, minutes: 9, tempC: 20),
      ],
    );

void main() {
  test('a roll developed before the chart existed gets one', () async {
    final Roll filled = await fillChart(
      _roll(),
      _Charting(<FilmChart>[_chart(3), _chart(9)]),
    );
    expect(filled.frames.every((Frame frame) => frame.isMeasured), isTrue);
    expect(filled.frames.first.patches, hasLength(9));
    expect(filled.frames.last.gamma, <double>[0.5, 0.59, 0.5]);
    // The roll is the same roll: only the measurement was missing.
    expect(filled.photo, '/photographs/uji.jpg');
    expect(filled.stockId, 'vision3_500t');
    expect(filled.frames.first.minutes, 3);
  });

  test('a model that cannot chart leaves the roll alone', () async {
    final Roll roll = _roll();
    expect(identical(await fillChart(roll, const _Charting(null)), roll), isTrue);
  });

  test('a charted roll is not charted twice', () async {
    final Roll once = await fillChart(
      _roll(),
      _Charting(<FilmChart>[_chart(3), _chart(9)]),
    );
    expect(identical(await fillChart(once, const _Charting(null)), once), isTrue);
  });
}
