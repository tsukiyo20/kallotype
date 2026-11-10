/// `3:00`, `12:30` — the clock a darkroom timer would show.
///
/// A development is minutes and a fraction, and this is how the darkroom says
/// it. It is not a duration: `9:00` in this product is a time of day that never
/// happens.
String darkroomClock(double minutes) {
  final int whole = minutes.floor();
  final int seconds = ((minutes - whole) * 60).round();
  return '$whole:${seconds.toString().padLeft(2, '0')}';
}
