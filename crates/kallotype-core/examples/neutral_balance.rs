//! Does the numerical grey balance still earn its keep with real dye spectra?
//!
//! Run with the digitised Vision3 500T curves:
//!
//! ```console
//! cargo run -p kallotype-core --example neutral_balance
//! ```

use kallotype_core::{PrintContext, ScanContext};
use kallotype_spectral::{Spectrum, load_csv};

fn read(stem: &str) -> Spectrum {
    let set = load_csv(format!("data/dyes/{stem}.csv")).expect("dye csv");
    set.samples[0].reflectance.clone()
}

fn main() {
    let placeholder = PrintContext::new([1.2, 1.1, 1.0]);
    let real = PrintContext::new([1.2, 1.1, 1.0]).with_dyes([
        read("vision3_500t_cyan"),
        read("vision3_500t_magenta"),
        read("vision3_500t_yellow"),
    ]);

    println!(
        "{:<10} {:>22} {:>22}",
        "density", "placeholder gains", "measured gains"
    );
    for step in 1..=10 {
        let density = 0.2 * f64::from(step);
        let a = placeholder.balance_gain(density);
        let b = real.balance_gain(density);
        println!(
            "{density:<10.1} [{:>6.3} {:>6.3} {:>6.3}] [{:>6.3} {:>6.3} {:>6.3}]",
            a[0], a[1], a[2], b[0], b[1], b[2]
        );
    }

    let full = PrintContext::new([1.2, 1.1, 1.0]).with_spectra(
        [
            read("vision3_500t_cyan"),
            read("vision3_500t_magenta"),
            read("vision3_500t_yellow"),
        ],
        [
            read("paper_endura_metallic_sensitivity_cyan"),
            read("paper_endura_metallic_sensitivity_magenta"),
            read("paper_endura_metallic_sensitivity_yellow"),
        ],
    );
    let masked = PrintContext::new([1.2, 1.1, 1.0])
        .with_spectra(
            [
                read("vision3_500t_cyan"),
                read("vision3_500t_magenta"),
                read("vision3_500t_yellow"),
            ],
            [
                read("paper_endura_metallic_sensitivity_cyan"),
                read("paper_endura_metallic_sensitivity_magenta"),
                read("paper_endura_metallic_sensitivity_yellow"),
            ],
        )
        .with_base_density(read("vision3_500t_minimum_density"));

    println!();
    println!("solving the enlarger filter pack on the measured model:");
    let solved = masked.solve_filters(1.0);
    println!(
        "  solved    {:.0}Y {:.0}M {:.0}C  (Kodak CC units)",
        solved[0], solved[1], solved[2]
    );
    let filtered = masked.clone().with_filters(solved);
    for density in [0.5, 1.0, 1.5, 2.0] {
        let g = filtered.balance_gain(density);
        let spread = g.iter().copied().fold(f64::NEG_INFINITY, f64::max)
            - g.iter().copied().fold(f64::INFINITY, f64::min);
        println!(
            "  D={density:>3.1}: gains [{:>5.3} {:>5.3} {:>5.3}] spread {spread:.3}",
            g[0], g[1], g[2]
        );
    }

    println!();
    println!("measured film dyes + papers + minimum density (the mask):");
    for step in 1..=10 {
        let density = 0.2 * f64::from(step);
        let g = masked.balance_gain(density);
        let spread = g.iter().copied().fold(f64::NEG_INFINITY, f64::max)
            - g.iter().copied().fold(f64::INFINITY, f64::min);
        println!(
            "  {density:>4.1}: gains [{:>5.3} {:>5.3} {:>5.3}] spread {spread:.3}",
            g[0], g[1], g[2]
        );
    }

    println!();
    println!("measured film dyes + measured paper layers:");
    for step in 1..=10 {
        let density = 0.2 * f64::from(step);
        let g = full.balance_gain(density);
        let spread = g.iter().copied().fold(f64::NEG_INFINITY, f64::max)
            - g.iter().copied().fold(f64::INFINITY, f64::min);
        println!(
            "  {density:>4.1}: gains [{:>5.3} {:>5.3} {:>5.3}] spread {spread:.3}",
            g[0], g[1], g[2]
        );
    }

    println!();
    println!("paper dyes in the scan, neutral densities (should be neutral):");
    let scan = ScanContext::new().with_dyes([
        read("paper_endura_metallic_cyan"),
        read("paper_endura_metallic_magenta"),
        read("paper_endura_metallic_yellow"),
    ]);
    for step in 1..=6 {
        let density = 0.3 * f64::from(step);
        let rgb = scan.scan([density; 3]);
        let spread = rgb.iter().copied().fold(f64::NEG_INFINITY, f64::max)
            - rgb.iter().copied().fold(f64::INFINITY, f64::min);
        println!(
            "  {density:>4.1}: rgb [{:>5.3} {:>5.3} {:>5.3}] spread {spread:.3}",
            rgb[0], rgb[1], rgb[2]
        );
    }

    println!();
    println!("spread of the gains (1.0 = the balance does nothing):");
    for step in 1..=10 {
        let density = 0.2 * f64::from(step);
        let spread = |g: [f64; 3]| {
            g.iter().copied().fold(f64::NEG_INFINITY, f64::max)
                - g.iter().copied().fold(f64::INFINITY, f64::min)
        };
        println!(
            "  {density:>4.1}: placeholder {:.3}   measured {:.3}",
            spread(placeholder.balance_gain(density)),
            spread(real.balance_gain(density))
        );
    }
}
