# Windows studio goldens

This folder is intentionally empty: the studio baselines committed today were
drawn on macOS. A Windows pass draws its own here, with the same widgets, the
same test card and the same fonts, but Windows' own text rasterisation.

From `app/` on Windows:

```bash
fvm flutter test --dart-define=studio-goldens=true --update-goldens \
  test/studio_golden_test.dart
```

Then, to compare:

```bash
fvm flutter test --dart-define=studio-goldens=true \
  test/studio_golden_test.dart
```

The files that appear are `select.png`, `select-light.png`, `develop.png`,
`print.png`, `rack.png`, `rack-light.png`, `viewer.png`, `gallery.png`,
`gallery-light.png`, `portrait.png`, `lens.png` and `loupe.png`. Commit them
beside the macOS set; the test reads only the folder for the platform it runs
on.
