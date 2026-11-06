//! The measured model, as a regression guard.
//!
//! Every other test in this crate runs on placeholders. These read the digitised
//! datasets, so they are where a physical regression would show up first.
//!
//! The grey balance is the thing to watch. It was written to compensate for
//! missing data; with the mask measured and the filter pack solved it should be
//! the identity. If it stops being the identity, something physical changed.

use std::path::Path;

use kallotype_core::{PrintContext, ScanContext};
use kallotype_spectral::{Spectrum, load_csv};

fn read(stem: &str) -> Spectrum {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../data/dyes")
        .join(format!("{stem}.csv"));
    let set = load_csv(&path).expect("dataset must load");
    set.samples[0].reflectance.clone()
}

fn film_dyes() -> [Spectrum; 3] {
    [
        read("vision3_500t_cyan"),
        read("vision3_500t_magenta"),
        read("vision3_500t_yellow"),
    ]
}

fn paper_layers() -> [Spectrum; 3] {
    [
        read("paper_endura_metallic_sensitivity_cyan"),
        read("paper_endura_metallic_sensitivity_magenta"),
        read("paper_endura_metallic_sensitivity_yellow"),
    ]
}

fn measured_print() -> PrintContext {
    PrintContext::new([1.2, 1.1, 1.0])
        .with_spectra(film_dyes(), paper_layers())
        .with_base_density(read("vision3_500t_minimum_density"))
}

fn spread(values: [f64; 3]) -> f64 {
    values.iter().copied().fold(f64::NEG_INFINITY, f64::max)
        - values.iter().copied().fold(f64::INFINITY, f64::min)
}

#[test]
fn the_solved_filter_pack_makes_the_balance_an_identity() {
    let context = measured_print();
    let filters = context.solve_filters(1.0);

    // The solved pack must look like something a colour head would accept. A
    // solution at 200Y or 0Y would mean the model is wrong, not the filter.
    assert!(
        (filters[0] - 97.0).abs() < 10.0,
        "yellow far from the expected range: {filters:?}"
    );
    assert!(filters[1] < 25.0, "magenta implausible: {filters:?}");

    let corrected = context.with_filters(filters);
    for density in [0.9, 1.0, 1.1] {
        let value = spread(corrected.balance_gain(density));
        assert!(
            value < 0.05,
            "D={density}: balance is not the identity ({value})"
        );
    }
}

#[test]
fn without_the_filter_pack_the_balance_has_real_work_to_do() {
    // The sentinel only means something if the uncorrected model fails it.
    let value = spread(measured_print().balance_gain(1.0));
    assert!(
        value > 1.0,
        "expected a large uncorrected spread, got {value}"
    );
}

#[test]
fn the_measured_scan_prints_neutral_grey() {
    let scan = ScanContext::new().with_dyes([
        read("paper_endura_metallic_cyan"),
        read("paper_endura_metallic_magenta"),
        read("paper_endura_metallic_yellow"),
    ]);

    for density in [0.3, 0.6, 0.9, 1.2] {
        let rgb = scan.scan([density; 3]);
        assert!(
            spread(rgb) < 0.01,
            "neutral density {density} drifted: {rgb:?}"
        );
        assert!(rgb[1] > 0.01, "density {density} clipped to black: {rgb:?}");
    }
}
