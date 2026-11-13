import 'package:flutter_test/flutter_test.dart';
import 'package:kallo_ui/lab/chart.dart';
import 'package:kallo_ui/lab/strip.dart';

FilmChart _chart(double minutes) => FilmChart(
  minutes: minutes,
  tempC: 20,
  gamma: <double>[0.5, 0.5, 0.5],
  dMin: <double>[0.05, 0.05, 0.05],
  dMax: <double>[3.0, 3.0, 3.0],
  patches: <List<double>>[
    for (int i = 0; i < 9; i++) <double>[0.1 * i, 0.1 * i, 0.1 * i],
  ],
  logE: <double>[for (int i = 0; i < 9; i++) -2.0 + i * 0.35],
);

TestPrint _print(double minutes) =>
    TestPrint(minutes: minutes, tempC: 20, chart: _chart(minutes));

void main() {
  test('the first print sets the one exposure, and later prints keep it', () {
    const TestStrip empty = TestStrip(photo: '/photographs/uji.jpg');
    expect(empty.balanceFrom, isNull);

    final TestStrip one = empty.withPrint(_print(9));
    expect(one.balanceFrom, 9);
    expect(one.prints, hasLength(1));

    final TestStrip two = one.withPrint(_print(12));
    expect(two.balanceFrom, 9, reason: 'the second print reuses the first');
    expect(two.prints, hasLength(2));
    // The strip reads left to right, whatever order the prints were made in.
    expect(two.prints.map((TestPrint p) => p.minutes), <double>[9, 12]);

    final TestStrip resorted = two.withPrint(_print(3));
    expect(resorted.prints.map((TestPrint p) => p.minutes), <double>[3, 9, 12]);
    expect(resorted.balanceFrom, 9);
  });

  test('a second print at the same time replaces the first', () {
    final TestStrip strip = const TestStrip(photo: '/photographs/uji.jpg')
        .withPrint(_print(9));
    final TestStrip again = strip.withPrint(_print(9));
    expect(again.prints, hasLength(1));
    expect(again.balanceFrom, 9);
  });

  test('removing the last print clears the exposure', () {
    final TestStrip strip = const TestStrip(photo: '/photographs/uji.jpg')
        .withPrint(_print(9));
    final TestStrip none = strip.without(9);
    expect(none.prints, isEmpty);
    expect(none.balanceFrom, isNull);
    expect(none.photo, '/photographs/uji.jpg');
  });

  test('a new strip keeps the photograph and forgets the prints', () {
    final TestStrip strip = const TestStrip(photo: '/photographs/uji.jpg')
        .withPrint(_print(9));
    final TestStrip fresh = strip.withoutPrints();
    expect(fresh.prints, isEmpty);
    expect(fresh.balanceFrom, isNull);
    expect(fresh.photo, '/photographs/uji.jpg');
  });

  test('the nearest print is the one a time looks at', () {
    final TestStrip strip = const TestStrip(photo: '/photographs/uji.jpg')
        .withPrint(_print(6))
        .withPrint(_print(12));
    expect(strip.printAt(9)?.minutes, 6);
    expect(strip.printAt(11)?.minutes, 12);
    expect(strip.latest?.minutes, 12);
  });
}
