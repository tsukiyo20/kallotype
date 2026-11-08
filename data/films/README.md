# The films that are not published as films

`data/films/` holds `.kalofilm` files for the stocks that are modelled but are
not released as films of the series:

| file | what it is |
|---|---|
| `vision3_500t/` | KODAK VISION3 500T — the stock the model started with, and the source of the shared dye and mask tables every other negative borrows |
| `fuji_nph400/` | FUJICOLOR NPH 400 PROFESSIONAL — the emulsion PRO 400H replaced |
| `fuji_c200/`, `fuji200/`, `fuji400/` | the consumer Fuji stocks, digitised from their own sheets |

They have no report, no `curves/` directory and no figures; what they have is the
same data format as `films/`, because the build reads both. The crate's stock
table is generated from `films/` and `data/films/` at build time
(`crates/kallotype-core/build.rs`): a file that is missing here is a stock that
disappears from `kalo stocks`.

The licence is the same as the films' — CC BY-SA 4.0, full text in
[`films/LICENSE`](../films/LICENSE). The code that reads these files is
Apache-2.0; the boundary between the two is a file read, not a comment.
