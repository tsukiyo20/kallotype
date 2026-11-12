//! `kalo stocks` — what is compiled in.

use kallotype_core::{FILM_STOCKS, PAPER_STOCKS};

/// Run the subcommand.
pub fn run(json: bool) {
    if json {
        println!("{}", kallotype_api::catalogue::json());
        return;
    }

    println!("film stocks");
    for stock in FILM_STOCKS {
        println!("  {:<22} {}", stock.id, stock.label);
        println!("  {:<22} {}", "", stock.note);
    }

    println!();
    println!("paper stocks");
    for stock in PAPER_STOCKS {
        println!("  {:<22} {}", stock.id, stock.label);
        println!("  {:<22} {}", "", stock.note);
    }
}
