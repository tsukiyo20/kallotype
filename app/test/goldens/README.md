# The studio's pictures, by platform

A golden belongs to the renderer that made it: the same widget tree, drawn on
macOS and Windows, is not the same pixels. So each platform keeps its own
baselines:

```
goldens/
  macos/     the twelve drawn on this Mac
  windows/   where a Windows pass draws its twelve
```

The test chooses its folder from `Platform`:

```dart
final String platform = Platform.isWindows ? 'windows' : 'macos';
matchesGoldenFile('goldens/$platform/select.png');
```

It is opt-in on both:

```bash
fvm flutter test --dart-define=studio-goldens=true \
  test/studio_golden_test.dart

fvm flutter test --dart-define=studio-goldens=true --update-goldens \
  test/studio_golden_test.dart
```

The twelve baselines are `select`, `select-light`, `develop`, `print`, `rack`,
`rack-light`, `viewer`, `gallery`, `gallery-light`, `portrait`, `lens` and
`loupe`. The lens is the frame under the wall's glass, with the loupe switch
beside the lamp; the loupe is that same frame walked up to, flat and at 1:1. The
portrait is the proof that a vertical frame turns the strip; the daylight set is
the proof that the neutral ramp and the physical materials hold in both
appearances; and the viewer is a print off the rack, full screen.

`--update-goldens` is the only way a baseline changes, and it changes only the
folder for the platform that ran it. CI runs `flutter test` without the define,
so no platform's pixels are compared on a third one.
