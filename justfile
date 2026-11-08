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

# Lint the camera raw crate, which is outside the workspace.
lint-raw:
    cd crates/kallotype-raw && cargo clippy --all-targets -- -D warnings

# Regenerate-and-compare the compiled stock table against the stock files.
#
# Local only: the stock files live in `private/`, which is not published, so CI
# cannot run this. It fails when a stock file and `emulsion.rs` disagree.
stocks:
    PYTHONPATH=private/.pylib313 /opt/homebrew/bin/python3.13 \
        private/scripts/compile_stocks.py --check private/stocks/kodak_portra_400.toml \
        private/stocks/kodak_portra_160.toml private/stocks/kodak_portra_800.toml \
        private/stocks/kodak_ektar_100.toml private/stocks/kodak_gold200.toml \
        private/stocks/fuji_nph400.toml private/stocks/fuji_c200.toml \
        private/stocks/fuji200.toml private/stocks/fuji400.toml \
        private/stocks/vision3_250d.toml private/stocks/vision3_50d.toml \
        private/stocks/vision3_200t.toml private/stocks/provia_100f.toml \
        private/stocks/ilford_delta400.toml private/stocks/kodak_tmax400.toml

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

clean:
    cargo clean
