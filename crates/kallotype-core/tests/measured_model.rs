//! The measured model, as a regression guard.
//!
//! Every other test in this crate runs on placeholders. These read the digitised
//! datasets, so they are where a physical regression would show up first.
//!
//! The datasets are **not in this repository**: they are the products of a
//! separate digitisation effort and are kept in the git-ignored `private/`
//! folder. Every test here is `#[ignore]`d for that reason. On a machine that has
//! that folder, run them with `cargo test -- --ignored`.
//!
//! Ignored tests rot, and these did: the dataset path was not updated when the
//! files moved into `private/`, and the four tests below were failing to find
//! their data for a commit before anyone ran them. They are worth running
//! whenever the model changes — `just data` does it.
//!
//! The grey balance is the thing to watch. It was written to compensate for
//! missing data; with the mask measured and the filter pack solved it should be
//! the identity. If it stops being the identity, something physical changed.

use std::path::Path;

use kallotype_core::{PrintContext, ScanContext, paper_stock};
use kallotype_spectral::{Spectrum, load_csv};

fn read(stem: &str) -> Spectrum {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../private/data/dyes")
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

#[ignore = "reads the digitised datasets, which are not in this repository"]
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

#[ignore = "reads the digitised datasets, which are not in this repository"]
#[test]
fn without_the_filter_pack_the_balance_has_real_work_to_do() {
    // The sentinel only means something if the uncorrected model fails it.
    let value = spread(measured_print().balance_gain(1.0));
    assert!(
        value > 1.0,
        "expected a large uncorrected spread, got {value}"
    );
}

#[ignore = "reads the digitised datasets, which are not in this repository"]
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

/// The measured minimum density is a mask, and a mask is only a mask if it is
/// consumed. This is the one test that needs the real spectrum: an unexposed
/// frame carries the orange cast, and developing the cyan layer takes it away.
#[ignore = "reads the digitised datasets, which are not in this repository"]
#[test]
fn the_orange_mask_is_consumed_by_cyan_development() {
    use kallotype_core::Masking;

    let clear = measured_print();
    let coupled = measured_print().with_masking(Masking::default());

    // Blue is the layer the mask absorbs in, so it is where the effect shows.
    // `expose` is anchored on a reference density, so compare gains, not levels.
    let clear_gain = coupled.expose([2.0, 0.0, 0.0])[2] - coupled.expose([0.0; 3])[2];
    let plain_gain = clear.expose([2.0, 0.0, 0.0])[2] - clear.expose([0.0; 3])[2];
    assert!(
        clear_gain > plain_gain + 0.02,
        "the mask gave back {:.3} decades of blue, not enough to be a coupler: {clear_gain} vs {plain_gain}",
        clear_gain - plain_gain
    );
}

/// Two columns of numbers, headed: log exposure and density.
fn curve_csv(stem: &str) -> Vec<(f64, f64)> {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../private/data/sensitometry")
        .join(format!("{stem}.csv"));
    let text = std::fs::read_to_string(&path).expect("dataset must load");
    text.lines()
        .skip(1)
        .filter(|line| !line.trim().is_empty())
        .map(|line| {
            let mut fields = line.split(',');
            let x = fields
                .next()
                .expect("a log exposure")
                .parse()
                .expect("a number");
            let y = fields.next().expect("a density").parse().expect("a number");
            (x, y)
        })
        .collect()
}

/// A paper stock carries one curve for three measured layers, which differ. The
/// stock is therefore the four-parameter fit of their *mean*, and that is what
/// this checks: recompute the mean from the data sheet and hold the compiled
/// curve to it. A parameter that drifted would show up here as an rms, not as a
/// plausible-looking curve.
#[ignore = "reads the digitised datasets, which are not in this repository"]
#[test]
fn the_measured_paper_curve_is_the_fit_of_its_three_layers_mean() {
    for (stock, stem) in [
        ("portra_endura", "portra_endura"),
        ("supra_endura", "supra_endura"),
        ("endura_premier_metallic", "paper_endura_premier_metallic"),
    ] {
        let paper = paper_stock(stock).unwrap_or_else(|| panic!("{stock} is not a stock"));
        let layers = ["red", "green", "blue"].map(|name| curve_csv(&format!("{stem}_{name}")));
        for layer in &layers {
            assert!(layer.len() > 200, "{stem}: only {} points", layer.len());
        }

        let mut sum = 0.0;
        let mut worst: f64 = 0.0;
        for (index, (log_e, _)) in layers[0].iter().enumerate() {
            let mean = layers.iter().map(|layer| layer[index].1).sum::<f64>() / 3.0;
            let error = paper.channel.density(*log_e) - mean;
            sum += error * error;
            worst = worst.max(error.abs());
        }
        let rms = (sum / layers[0].len() as f64).sqrt();
        assert!(rms < 0.03, "{stock}: rms {rms:.4} against the layer mean");
        assert!(
            worst < 0.07,
            "{stock}: worst {worst:.4} against the layer mean"
        );

        // And the mean cannot have been mistaken for one of the layers: the
        // layers differ at the shoulder, most of all on the metallic sheet.
        let shoulder = |layer: &Vec<(f64, f64)>| layer[layer.len() - 10].1;
        let spread = layers
            .iter()
            .map(&shoulder)
            .fold(f64::NEG_INFINITY, f64::max)
            - layers.iter().map(&shoulder).fold(f64::INFINITY, f64::min);
        assert!(
            spread > 0.05,
            "{stock}: the layers only differ by {spread:.3}, so this test proves little"
        );
    }
}
