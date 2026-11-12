//! The catalogue: what is compiled in, as a document a program can read.

use kallotype_core::{
    FILM_STOCKS, FilmProcess, FilmStock, PAPER_STOCKS, PaperEmulsion, PaperStock, Provenance,
};
use serde_json::{Map, Value, json};

/// The words a `[measured]` line may begin with, before its colon.
///
/// They are the format's own vocabulary — `data/films/FORMAT.md` — and this is
/// the one place that reads them, so that a program asking for the catalogue
/// gets a verdict rather than a sentence it has to parse itself.
const CLAIMS: [&str; 4] = ["measured", "borrowed", "placeholder", "none"];

/// Every stock, as a document a program can read.
///
/// The same data the renderer uses, produced by the same build from the same
/// files: a shelf that showed a film the model did not have would be an
/// interface lying about its own model, and a catalogue generated separately
/// would be that lie with a schema.
/// Every stock, as a document a program can read.
pub fn value() -> Value {
    json!({
        "schema": "kallotype/catalogue/1",
        "films": FILM_STOCKS.iter().map(film).collect::<Vec<Value>>(),
        "papers": PAPER_STOCKS.iter().map(paper).collect::<Vec<Value>>(),
    })
}

fn film(stock: &FilmStock) -> Value {
    json!({
        "id": stock.id,
        "short": stock.short,
        "label": stock.label,
        "process": process(stock.process),
        "note": stock.note,
        "reference": {
            "minutes": stock.reference_time_min,
            "temp_c": stock.reference_temp_c,
        },
        "provenance": provenance(&stock.provenance),
        "measured": measured(stock.measured),
    })
}

fn paper(stock: &PaperStock) -> Value {
    json!({
        "id": stock.id,
        "short": stock.short,
        "label": stock.label,
        // What the paper carries, in the word the app groups the shelf by.
        "emulsion": match stock.emulsion {
            PaperEmulsion::Colour => "colour",
            PaperEmulsion::Silver => "silver",
        },
        "note": stock.note,
        "provenance": provenance(&stock.provenance),
        "measured": measured(stock.measured),
    })
}

fn process(process: FilmProcess) -> &'static str {
    match process {
        FilmProcess::Negative => "negative",
        FilmProcess::Reversal => "reversal",
        FilmProcess::Monochrome => "monochrome",
    }
}

fn provenance(provenance: &Provenance) -> Value {
    json!({
        "publication": provenance.publication,
        "page": provenance.page,
        "retrieved": provenance.retrieved,
        "checksum": provenance.checksum,
    })
}

/// What each field admits to, with the verdict split off the sentence.
///
/// `{"field": "grain", "claim": "placeholder", "detail": "the sheet prints a
/// Print Grain Index …"}`. A line that does not begin with a claim keeps its
/// whole text as the detail and an empty claim, which is the honest reading of
/// a sentence the format did not anticipate.
fn measured(rows: &[(&str, &str)]) -> Vec<Value> {
    rows.iter()
        .map(|(field, text)| {
            let (claim, detail) = split(text);
            let mut row = Map::new();
            row.insert("field".to_owned(), json!(field));
            row.insert("claim".to_owned(), json!(claim));
            row.insert("detail".to_owned(), json!(detail));
            Value::Object(row)
        })
        .collect()
}

/// Split `claim: detail`, or `claim`, into its two halves.
fn split(text: &str) -> (&str, &str) {
    match text.split_once(':') {
        Some((head, rest)) if is_claim(head) => (head, rest.trim()),
        _ if is_claim(text) => (text, ""),
        _ => ("", text),
    }
}

fn is_claim(word: &str) -> bool {
    let word = word.trim();
    CLAIMS.iter().any(|claim| claim.eq_ignore_ascii_case(word))
}

/// The catalogue as one document for a caller that speaks JSON.
#[must_use]
pub fn json() -> String {
    serde_json::to_string(&value()).expect("a catalogue of strings is serialisable")
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The catalogue is the model's own list, not a list about it.
    #[test]
    fn every_stock_is_in_the_catalogue() {
        let Value::Array(films) = &value()["films"] else {
            panic!("no films");
        };
        assert_eq!(films.len(), FILM_STOCKS.len());
        assert!(!films.is_empty());
        let Value::Array(papers) = &value()["papers"] else {
            panic!("no papers");
        };
        assert_eq!(papers.len(), PAPER_STOCKS.len());
    }

    /// Every film says where it came from, and what each field admits to.
    ///
    /// A catalogue entry without a provenance would be a shelf with the labels
    /// torn off, and the note is what the app shows a person who asks why a
    /// film looks the way it does.
    ///
    /// A line that does not begin with one of the four verdicts is allowed and
    /// is passed through whole: a file that says "measured (old emulsion)" is
    /// making a narrower claim than the vocabulary can carry, and flattening it
    /// to one of the four would be the catalogue losing the file's nuance.
    #[test]
    fn every_film_cites_its_sheet_and_its_borrows() {
        for stock in FILM_STOCKS {
            assert!(
                !stock.provenance.publication.is_empty(),
                "{} cites no publication",
                stock.id
            );
            assert!(!stock.measured.is_empty(), "{} admits to nothing", stock.id);
            assert!(!stock.note.trim().is_empty(), "{} has no note", stock.id);
            for (field, text) in stock.measured {
                assert!(
                    !text.trim().is_empty(),
                    "{} says nothing about its {field}",
                    stock.id
                );
            }
        }
    }

    /// A paper says what it carries, and a silver one says so.
    ///
    /// A colour film printed on a silver paper is a black-and-white print in
    /// the world and a colour print in this model, so the catalogue has to be
    /// able to tell a shelf which papers are which.
    #[test]
    fn the_papers_say_what_they_carry() {
        let silver: Vec<&str> = PAPER_STOCKS
            .iter()
            .filter(|paper| paper.emulsion == PaperEmulsion::Silver)
            .map(|paper| paper.id)
            .collect();
        assert_eq!(silver, ["polymax_ii_rc"]);
        assert!(
            PAPER_STOCKS
                .iter()
                .any(|paper| paper.emulsion == PaperEmulsion::Colour),
            "no colour paper to print a colour film on"
        );
        let Value::Array(papers) = &value()["papers"] else {
            panic!("no papers");
        };
        for paper in papers {
            let emulsion = paper["emulsion"].as_str().expect("an emulsion");
            assert!(emulsion == "colour" || emulsion == "silver", "{emulsion}");
        }
    }

    /// The split survives the three shapes the files actually contain.
    #[test]
    fn the_claim_comes_off_the_sentence() {
        assert_eq!(
            split("measured: page 4, three curves"),
            ("measured", "page 4, three curves")
        );
        assert_eq!(split("borrowed"), ("borrowed", ""));
        assert_eq!(
            split("none: a reversal has no orange mask"),
            ("none", "a reversal has no orange mask")
        );
        assert_eq!(
            split("the sheet prints 0.4 at 5 nm: a note"),
            ("", "the sheet prints 0.4 at 5 nm: a note")
        );
    }
}
