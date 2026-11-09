# Working in this repository

Two build units, one tree.

| | |
|---|---|
| `crates/` | the model, in Rust. A `cargo` workspace, published to crates.io. |
| `app/` | the interface, in Flutter. Its `pubspec.yaml` lives in `app/`. |

## The one law

`app/lib/film/film.dart` holds a **stand-in** for the Rust model — enough of the
H&D curve to draw a strip with. The file says so at the top. The real numbers
come from `kallotype-view`, which does not exist yet.

Nothing in that file may grow into a second implementation of the physics. If a
change needs a curve, a density or a grain, it needs `kallotype-view` first.

## The app has no Material

No `MaterialApp`, no `Material`, no `Card`, no `InkWell`, no elevation — and
`uses-material-design: false` in `app/pubspec.yaml` is where that is written
down. This is not an oversight; the design language is the product.

Read `app/README.md` before changing anything visible. Its seven rules — no
shadows for depth, one accent, five type roles, six spacing steps, hairlines are
one device pixel, nothing animates alone, the film is geometry — are the review
checklist.

## Where things live

- `app/lib/design/tokens.dart` — colours, space, radii, motion, type. A visual
  change usually belongs here, not in a widget.
- `app/lib/design/scope.dart` — the two environments, and the `emissive` value
  the transition interpolates.
- `app/lib/film/film.dart` — 35 mm geometry and the strip painter.
- `app/test/goldens/` — the two pictures the design is held against.

## Verifying

```bash
just check                    # Rust: fmt, clippy, tests
cd app && flutter analyze     # must say "No issues found!"
cd app && flutter test        # goldens skip off Windows, on purpose
```

The goldens are drawn with the machine's own fonts, so their baseline is Windows
and the test skips elsewhere. `flutter test --update-goldens` rewrites them
deliberately — never as a way to turn a red test green.

## Commits

`type(scope): a lower-case sentence saying what the commit does`, not a label:

```
feat(enlarger): the criterion the stage can actually meet
chore(licence): the code goes dual MIT/Apache-2.0
```

One idea per commit. The subject says what changed; the body says why.

## Skills

`.agents/skills/` holds 25 skills vendored from `flutter/agent-plugins` and
`dart-lang/skills`, in the `<name>/SKILL.md` layout. Its `README.md` has the
provenance and the licences. They are not written here and are not modified
here; a fix belongs upstream.

## With a Dart MCP server connected

`dart mcp-server` ships with the SDK and needs no installation. Point your
client at it if you want the analyzer, the test runner, the widget inspector and
hot reload as tools; the configuration is per machine and is not committed.

After editing a `.dart` file under `app/lib/`, apply the official rule: call
`hot_reload` for widget changes, `hot_restart` when `main()`, `initState` or
global state changed, and skip both for edits outside `lib/` and for
comment-only changes. Adapted from
[`flutter/agent-plugins`](https://github.com/flutter/agent-plugins/blob/main/rules/flutter-hot-reload.md).
