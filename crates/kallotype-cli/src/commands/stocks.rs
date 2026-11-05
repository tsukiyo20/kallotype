//! `kalo stocks` — what is compiled in.

use kallotype_core::{FILM_STOCKS, PAPER_STOCKS};

/// Run the subcommand.
pub fn run() {
    println!("film stocks");
    for stock in FILM_STOCKS {
        println!("  {:<14} {}", stock.id, stock.label);
        println!("  {:<14} {}", "", stock.note);
    }

    println!();
    println!("paper stocks");
    for stock in PAPER_STOCKS {
        println!("  {:<14} {}", stock.id, stock.label);
        println!("  {:<14} {}", "", stock.note);
    }
}
