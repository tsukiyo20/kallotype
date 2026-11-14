# Local workflow. CI runs the same commands; `just` is a convenience, not a
# requirement — every recipe is a plain cargo invocation you can type instead.

set shell := ["bash", "-c"]

default:
    @just --list

# Format the tree.
fmt:
    cargo fmt --all

# Fail if anything is unformatted.
fmt-check:
    cargo fmt --all --check

# Lint everything, warnings are errors.
#
# `--all-features` because that is what CI lints with: a warning that only
# appears in the graph with `raw` or `gpu` on passes here and fails there.
lint:
    cargo clippy --workspace --all-targets --all-features -- -D warnings

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

# Check the app's binding crate.
#
# It is its own workspace because Flutter's native-assets hook builds it, not
# `cargo build` at the root — and because flutter_rust_bridge rewrites
# `src/frb_generated.rs` on every generation, which `cargo fmt --all` should
# not touch.
ffi:
    cd app/rust && cargo check --all-targets

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

# Render a photograph through the model, into the folder the app reads.
#
# A print is not an asset: it is output. The app ships no pictures, the gallery
# hangs whatever is in the export folder, and an app that has not printed
# anything has an empty wall — which is the state it is built to show. Nothing
# here is committed.
#
# The export lands in `Pictures/Kallotype` under $HOME unless a fourth argument
# says otherwise — that is the app's default folder, not a promise that it is
# the one you chose in the drawer.
#
# Example: just print ../file-test/DSCF0989.JPG
#          just print ../file-test/DSCF0989.JPG 12 20 ~/Desktop/prints
print src dev="9" temp="20" dest="$HOME/Pictures/Kallotype":
    mkdir -p "{{dest}}"
    cargo run --release --quiet --bin kalo -- render {{src}} -o "{{dest}}/print-{{dev}}min.png" --film vision3_500t --paper fuji_crystal_archive_pearl --dev {{dev}} --temp {{temp}} --ev auto --grain --halation --couplers

# Write the strip the app draws, from the model.
#
# The result is committed as an app asset so that building the interface needs
# no Rust toolchain. Regenerate it; never edit it.
# Example: just view vision3_500t app/assets/film_strip.json
view *args:
    cargo run --quiet -p kallotype-view --bin kaloview -- {{args}}

clean:
    cargo clean
