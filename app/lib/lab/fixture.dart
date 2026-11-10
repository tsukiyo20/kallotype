import '../film/strip_data.dart';
import 'roll.dart';

/// A layout fixture, and nothing else.
///
/// The committed strip holds five developments of one wedge — the model's own
/// output, and the only roll there is until the model sits behind an FFI. Five
/// frames is not enough to see how a sheet behaves at a full roll, so this
/// builds forty by interpolating between the measured ones.
///
/// It is not model output. It is not shipped as an asset, it never stands in
/// for a render, and the app only opens it when asked
/// (`--dart-define=roll36`). Every number in it is a straight line between two
/// numbers the model did produce.
Roll interpolatedRoll(StripData strip, {int frames = 40}) {
    final List<StripFrame> measured = strip.frames;
    final List<Frame> built = <Frame>[];
    final double first = measured.first.minutes;
    final double last = measured.last.minutes;
    for (int i = 0; i < frames; i++) {
      final double minutes = first + (last - first) * i / (frames - 1);
      int lower = 0;
      for (int k = 0; k < measured.length - 1; k++) {
        if (minutes >= measured[k].minutes && minutes <= measured[k + 1].minutes) {
          lower = k;
          break;
        }
        lower = k;
      }
      final StripFrame a = measured[lower];
      final StripFrame b = measured[lower + 1 < measured.length
          ? lower + 1
          : measured.length - 1];
      final double span = b.minutes - a.minutes;
      final double t = span <= 0 ? 0 : (minutes - a.minutes) / span;
      built.add(Frame(
        number: i + 1,
        minutes: minutes,
        tempC: a.tempC + (b.tempC - a.tempC) * t,
        gamma: _lerp(a.gamma, b.gamma, t),
        dMax: _lerp(a.dMax, b.dMax, t),
        patches: <List<double>>[
          for (int p = 0; p < a.patches.length; p++)
            _lerp(a.patches[p], b.patches[p], t),
        ],
      ));
    }
    return Roll(
      number: 1,
      stockId: strip.stockId,
      stockLabel: strip.label,
      frames: built,
    );
  }

List<double> _lerp(List<double> a, List<double> b, double t) =>
    <double>[for (int i = 0; i < a.length; i++) a[i] + (b[i] - a[i]) * t];
