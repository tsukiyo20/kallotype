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
lint:
    cargo clippy --workspace --all-targets --all-features -- -D warnings

# Run the whole test suite.
test:
    cargo test --workspace --all-features

# Build the API documentation, warnings are errors.
doc:
    cargo doc --workspace --no-deps

# Everything CI checks.
check: fmt-check lint test

# Render an image. Example: just run render assets/testchart.png -o out/a.png --dev 9
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
