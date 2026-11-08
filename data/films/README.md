# Film data for stocks without a report

`data/films/` holds `.kalofilm` files for stocks that are modelled but are not
released as films of the series. Today it is **empty of data**: the five stocks
that used to live here — VISION3 500T, NPH 400, C200, FUJI 200 and FUJI 400 —
were published as films 17 to 21 and their files moved to `films/`.

The directory stays because the build reads it: a new modelled stock that is not
yet a film belongs here, and `crates/kallotype-core/build.rs` scans it beside
`films/`.

The licence is the same as the films' — CC BY-SA 4.0, full text in
[`films/LICENSE`](../films/LICENSE).
