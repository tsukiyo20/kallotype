# Local workflow. CI runs the same commands; `just` is a convenience, not a
# requirement — every recipe is a plain cargo invocation you can type instead.

set shell := ["bash", "-c"]

default:
    @just --list

# Build `kalo` with camera raw decoding.
#
# This pulls in `kallotype-raw`, which is LGPL-2.1 through `rawler`, so the
# binary is a combined work. It lives outside the workspace so that the default
# build, `just lint` and `just deny` are Apache-2.0 all the way down.
raw:
    cargo build --release --bin kalo --features raw

# Format the tree.
fmt:
    cargo fmt --all

# Fail if anything is unformatted.
#
# `kallotype-raw` is outside the workspace and so is not reached by
# `cargo fmt --all`; it is formatted directly.
fmt-check:
    cargo fmt --all --check
    rustfmt --edition 2024 --check crates/kallotype-raw/src/lib.rs

# Lint everything, warnings are errors.
#
# Default features on purpose: `--all-features` would enable `raw` and drag the
# LGPL decoder into the graph this recipe is meant to keep Apache-2.0. The raw
# crate has its own recipe below.
lint:
    cargo clippy --workspace --all-targets -- -D warnings

# The lint CI runs, which is not the one above.
#
# CI lints with `--all-features`, so a warning that only appears in that graph
# passes here and fails there. Run this before pushing; the cost is that the
# LGPL decoder is compiled locally for the lint.
lint-ci:
    cargo clippy --workspace --all-targets --all-features -- -D warnings

# Lint the camera raw crate, which is outside the workspace.
lint-raw:
    cd crates/kallotype-raw && cargo clippy --all-targets -- -D warnings

# Repack every stock file in a scratch directory and compare it with the
# `.kalofilm` the build reads. The crate no longer carries the film data: the
# films are files, and a stock file that has moved since its film was packed is
# a render that disagrees with the record.
#
# Local only: the stock files live in `private/`, which is not published, so CI
# cannot run this.
stocks:
    PYTHONPATH=private/.pylib313 /opt/homebrew/bin/python3.13 \
        private/scripts/check_film_files.py

# Run the whole test suite.
test:
    cargo test --workspace --all-features

# Run the tests that read the digitised datasets in the private folder.
#
# These are `#[ignore]`d because the data is not in the repository, so nothing in
# CI runs them and nothing notices when they stop working. Run them whenever the
# model or the datasets move.
data:
    cargo test --workspace --all-features -- --ignored

# Build the API documentation, warnings are errors.
doc:
    cargo doc --workspace --no-deps

# Everything CI checks.
check: fmt-check lint test

# Render an image. Example: just run render crates/kallotype-cli/assets/testchart.png -o out/a.png --dev 9
run *args:
    cargo run --release --bin kalo -- {{args}}

# Compare RGB → spectrum reconstructions.
bench *args:
    cargo run --release -p kallotype-spectral --bin kalo-bench -- {{args}}

# Audit licences, advisories and sources.
deny:
    cargo deny check

# Write the print the gallery hangs, and the record of how it was made.
#
# The image is the model's: a photograph developed, printed on paper and saved
# as sRGB. The record beside it is the same invocation written down, so that the
# app can label the print without guessing — the model does not write one yet,
# and when it does this second line goes.
#
# The source photograph is the author's own and is not in this repository; it
# lives in the private tree, so it is passed in.
# Example: just print private/raw/user/fuji_1200.jpg
print src dev="9" temp="20":
    cargo run --release --quiet --bin kalo -- render {{src}} -o app/assets/print.png --film vision3_500t --paper fuji_crystal_archive_pearl --dev {{dev}} --temp {{temp}} --ev auto --grain
    printf '{\n  "film": "VISION3 500T",\n  "paper": "CRYSTAL ARCHIVE PEARL",\n  "minutes": %s,\n  "temp_c": %s\n}\n' "{{dev}}" "{{temp}}" > app/assets/print.json

# Write the strip the app draws, from the model.
#
# The result is committed as an app asset so that building the interface needs
# no Rust toolchain. Regenerate it; never edit it.
# Example: just view vision3_500t app/assets/film_strip.json
view *args:
    cargo run --quiet -p kallotype-view --bin kaloview -- {{args}}

clean:
    cargo clean
