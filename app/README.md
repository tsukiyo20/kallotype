# app
The interface of Kallotype.

This is not a widget library and not a design system for other people to use.
It is **this app's vocabulary**, written down once so that every screen after it
is the same product.

It is also small on purpose. If it grows past a few thousand lines it has become
a framework, and a framework is a thing you maintain instead of a thing you
ship.

---

## Run it

```bash
cd app
flutter run -d windows
```

The `windows/` platform folder is checked in. For the Mac, where this app is
meant to live:

```bash
flutter create --platforms=macos --project-name kallo_ui .
rm test/widget_test.dart   # the scaffold test refers to a MaterialApp we do not have
```

There is no `MaterialApp` anywhere, and that is the point.

---

## What is verified

`flutter analyze` is clean, and two golden tests pin the language:

| light table | darkroom |
|---|---|
| ![the light table](test/goldens/light_table.png) | ![the darkroom](test/goldens/darkroom.png) |

```bash
flutter test                    # compares against the two images
flutter test --update-goldens   # rewrites them, deliberately
```

The test loads the machine's own faces 鈥?Segoe UI for Latin, DengXian for the
Chinese, Consolas standing in for Menlo 鈥?because the test renderer otherwise
draws every glyph as a box, and a design judged on its type cannot be judged as
boxes. See `test/gallery_golden_test.dart`.

`docs/window.png` is the real Windows build, captured from a running window.


---

## What you are looking at

One screen, four arguments:

| | |
|---|---|
| **Two places, not two themes** | A darkroom is lit by one safelight. A light table is a light source. The toggle at the top right moves between *lighting*, and everything that glows is multiplied by a single interpolated `emissive`. |
| **The film is the artifact** | The strip is drawn in millimetres 鈥?35 mm wide, 24 mm frames, 38 mm pitch, 5.5 mm rebates 鈥?and the UI labels it from outside. Film is material; UI is annotation. |
| **Time is a dimension** | The five frames are the same frame developed for 3, 6, 9, 12 and 15 minutes. The wedge on each one is the same nine-step exposure put through the H&D curve at that frame's 纬. Longer development is visibly more contrast, and it is not a filter. |
| **Nothing is a default** | No ripple, no elevation, no Roboto, no colour roles, no 4 dp grid. |

---

## The rules

These are the ones worth enforcing in review.

1. **No `MaterialApp`. No `Material`, `Card`, `Elevation`, `InkWell`.**
   `WidgetsApp` gives text direction, focus, overlay, semantics and routing.
   It gives nothing else. `uses-material-design: false` in `pubspec.yaml` is
   where that is written down.

2. **No shadows for depth.** A thing is raised by being lighter than what is
   behind it, and by a hairline. `BoxShadow` appears exactly once in this code,
   on the film strip, and it means *light*, not height.

3. **One accent.** The safelight. Everything else is a neutral on one
   luminance ramp, because the contrast in this product is density 鈥?which is
   brightness 鈥?and not hue.

4. **Five type roles, six spacing steps, two radii.** When you need a new one,
   the layout is usually wrong. `KalloSpace` has no step 12 or 24; that gap is
   the whole reason it reads as deliberate.

5. **Hairlines are one device pixel, not one logical pixel.** On a Retina
   screen those are different, and the difference is a seam.

6. **Nothing animates alone.** `KalloMotion.stagger` is 40 ms. If three things
   move, they move 40 ms apart.

7. **The film is geometry, not sticker art.** `FilmMetrics` is the single
   source of the strip's measurements; the painter and the label row both read
   from it, so the labels stay under their frames at any width.

---

## Tokens

`lib/design/tokens.dart` is the whole visual contract.

- **Colours** 鈥?two complete sets, `darkroom` and `lightTable`, plus
  `KalloColors.lerp`. The `emissive` field is a `double` rather than a flag
  precisely so it can be interpolated; everything that appears to give off
  light reads it.
- **Space** 鈥?2, 4, 8, 16, 32, 64.
- **Radius** 鈥?1.5 for film, 12 for sheets. Nothing between.
- **Motion** 鈥?90 / 160 / 240 / 460 ms, three curves, one stagger.
- **Type** 鈥?`display`, `title`, `body`, `caption`, `data`. The `data` role is
  monospaced with tabular figures, because it is for numbers that change while
  you look at them and nothing around them may move.

There is no brand typeface yet. `KalloType.sans` is `null`, which means the
platform's own face. When one is chosen it goes there and nowhere else.

---

## What is deliberately not here

- **The model.** The wedge on the strip is not drawn here. It is read from
  `assets/film_strip.json`, which `just view` writes from `kallotype-view`, so
  the five frames are VISION3 500T developed for 3, 6, 9, 12 and 15 minutes and
  not a shape invented to look like one. Regenerate it; never edit it.
- **Colour management.** The screen is not tagged, nothing is P3, and the
  light table is therefore not yet truthful. This is the next hard thing.
- **Text input.** `EditableText`, selection, IME and accessibility are the
  framework's job. Do not rebuild them; rebuild everything you can see.
- **A real darkroom.** The room is a pre-rendered plate with a few live quads
  on top. This code starts at the light table because that is where the design
  language can be judged in a week.

---

## How to judge it

Screenshot the light table, remove the text, and look at it.

If it still reads as *this* product, the language is working. If it reads as a
Flutter app, the problem is in one of the seven rules above 鈥?not in a library.
