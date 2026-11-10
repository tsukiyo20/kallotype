# assets

Two kinds of file, and neither is drawn by the app.

| file | who writes it | how to regenerate |
|---|---|---|
| `film_strip.json` | the model, through `kallotype-view` | `just view vision3_500t app/assets/film_strip.json` |
| `print.png`, `print.json` | the model, through `kalo render` | `just print <the photograph>` |

Both are renderings of the model at a commit, not a second model: **regenerate
them, never edit them**. `print.json` is the invocation written down, which is
what the app reads to label the print; when the model writes its own record,
that line in the justfile goes away.

## The photograph

`print.png` is a photograph the project's author took, in Uji, and it is in this
repository with their permission, as the sample print the gallery hangs. It is
**not** covered by the MIT or Apache licence that covers the code, and it should
not be reused as though it were.
