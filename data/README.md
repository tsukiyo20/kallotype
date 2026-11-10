# data

Everything the renderer is built from, and nothing it is not: two kinds of
measured stock, each in the file format its own sheet produced.

| directory | what is in it |
|---|---|
| [`films/`](films/) | the published series — twenty-four films, each a directory with its `.kalofilm`, its report, its digitised points and its figures. Start at [`films/README.md`](films/README.md). |
| [`papers/`](papers/) | six measured papers, one `.kalopaper` each. [`papers/README.md`](papers/README.md) says which and why. |

The crate holds none of these numbers. `crates/kallotype-core/build.rs` reads
the `.kalofilm` and `.kalopaper` files here when the crate is built and
generates the stock tables from them, so the program text is MIT or Apache-2.0
and this directory is CC BY-SA 4.0, with the boundary at a file read rather
than at a comment. Building from source therefore needs this directory present.

## What a file is

A `.kalofilm` is the film: a TOML header that says where every number came from,
the spectra as binary tables in a fixed order, and a SHA-256 over the lot. A
`.kalopaper` is the same container with a different magic and one curve instead
of three. Both formats are specified in [`films/FORMAT.md`](films/FORMAT.md),
which also documents the TOML source file a stock is authored in and the four
things `kalo stock check` refuses.

No image of a data sheet is reproduced anywhere in here. The sheets stay with
their publishers; what this project produced is the numbers read from them, and
each file names the publication, the page and the SHA-256 of the document it was
read from.

## Licence

The data is **CC BY-SA 4.0**: use it for anything, including commercially,
provided the adaptation is shared under the same terms. The full text is in
[`films/LICENSE`](films/LICENSE), which also records that the three films
published before 2026-11-09 went out under CC BY 4.0 and that those copies keep
that grant. Trademarks and what is not redistributed are in
[`films/NOTICE.md`](films/NOTICE.md).
