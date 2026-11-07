//! A stock as data: the file format, its parser, and its checker.
//!
//! ADR 0012 in the private folder argues that a stock should be a file rather
//! than a `&'static` struct in `emulsion.rs`, because the cost of the *n*th
//! stock is otherwise an edit to the model. This module is the format and the
//! gate: `kalo stock check` reads one, refuses one that claims to be measured
//! without naming its document, and re-derives the curve from the digitised
//! points to catch a transcription slip.
//!
//! ## The format
//!
//! TOML, in the subset this parser accepts: `[section]` and `[section.key]`
//! headers, `key = value` pairs, `#` comments, double-quoted strings with no
//! escapes, numbers, and single-line arrays of either. That is enough for every
//! field a stock has, and it keeps the file readable and hand-editable without
//! pulling a serialiser into a crate that has one dependency.
//!
//! ```toml
//! [stock]
//! id = "portra_endura"
//! kind = "paper"            # or "film"
//! claim = "measured"        # or "placeholder"
//!
//! [provenance]
//! publication = "E-4021"
//! page = 7
//! retrieved = "2026-11-07"
//! checksum = "sha256:04691bc2..."
//!
//! [curve.red]
//! d_min = 0.0909
//! d_max = 2.6087
//! gamma = 3.68
//! log_e0 = -1.4125
//! transition = 7.0
//! points = "data/sensitometry/portra_endura_red.csv"
//! rms = 0.017
//! ```
//!
//! ## What the checker enforces
//!
//! 1. A stock that says `claim = "measured"` must name the document, the page,
//!    the retrieval date and the checksum of the file it came from. Without them
//!    it is a placeholder, whatever it says.
//! 2. The curve has to be a curve: `d_min < d_max`, positive `gamma`, and a
//!    transition that is not zero.
//! 3. If the stock names the digitised points, **the numbers are re-derived from
//!    them** and the fit's rms must be what the file claims. A transposed digit
//!    fails here instead of rendering plausibly.
//! 4. If it names spectra, each must be a 71-sample grid from 380 to 730 nm at
//!    5 nm — the grid the model integrates on — with finite, non-negative values.

use std::collections::BTreeMap;
use std::fmt;
use std::path::{Path, PathBuf};

use kallotype_core::CharacteristicCurve;

/// What a stock file said, and where it said it.
#[derive(Debug, Clone)]
pub struct StockFile {
    /// The path it was read from, for messages.
    pub path: PathBuf,
    /// The parsed keys, section-qualified.
    table: BTreeMap<String, Value>,
}

impl StockFile {
    /// Read and parse a stock file.
    ///
    /// # Errors
    ///
    /// Fails on a read error, a syntax error, or a missing required field.
    pub fn read(path: impl AsRef<Path>) -> Result<Self, StockError> {
        let path = path.as_ref().to_path_buf();
        let text = std::fs::read_to_string(&path).map_err(|source| StockError::Io {
            path: path.clone(),
            source,
        })?;
        let table = parse(&text, &path)?;
        let file = Self { path, table };
        file.require(&["stock.id", "stock.label", "stock.kind", "stock.claim"])?;
        let kind = file.string("stock.kind")?;
        if kind != "film" && kind != "paper" {
            return Err(file.fail(format!(
                "stock.kind is {kind:?}; a stock is \"film\" or \"paper\""
            )));
        }
        let claim = file.string("stock.claim")?;
        if claim != "measured" && claim != "placeholder" {
            return Err(file.fail(format!(
                "stock.claim is {claim:?}; it is \"measured\" or \"placeholder\""
            )));
        }
        Ok(file)
    }

    /// Where the file came from.
    #[must_use]
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// The stock's id.
    ///
    /// # Errors
    ///
    /// Cannot fail: `read` required it.
    pub fn id(&self) -> String {
        self.string("stock.id").unwrap_or_default()
    }

    /// The stock's human-readable name.
    ///
    /// # Errors
    ///
    /// Cannot fail: `read` required it.
    pub fn label(&self) -> String {
        self.string("stock.label").unwrap_or_default()
    }

    /// Whether this is a film or a paper.
    ///
    /// # Errors
    ///
    /// Cannot fail: `read` required it.
    pub fn is_film(&self) -> bool {
        self.string("stock.kind")
            .map(|k| k == "film")
            .unwrap_or(false)
    }

    /// Whether this is a reversal film, whose curve falls with exposure.
    ///
    /// # Errors
    ///
    /// Cannot fail: an absent `stock.process` is a negative.
    pub fn is_reversal(&self) -> bool {
        self.string("stock.process")
            .map(|p| p == "reversal")
            .unwrap_or(false)
    }

    /// Whether the file claims the numbers were measured.
    #[must_use]
    pub fn claims_measured(&self) -> bool {
        self.string("stock.claim")
            .map(|c| c == "measured")
            .unwrap_or(false)
    }

    /// Run every check and collect what they found.
    #[must_use]
    pub fn check(&self) -> Vec<Finding> {
        let mut findings = Vec::new();
        findings.push(self.check_provenance());
        findings.push(self.check_process());
        findings.push(self.check_borrowed());
        findings.extend(self.check_curves());
        findings.push(self.check_base());
        findings.push(self.check_emulsion());
        findings.extend(self.check_spectra());
        findings
    }

    /// A stock that claims to be measured must say where its numbers came from.
    fn check_provenance(&self) -> Finding {
        if !self.claims_measured() {
            return Finding::note(
                "provenance",
                "placeholder: no document is claimed, and the render says so",
            );
        }
        let mut missing = Vec::new();
        for key in [
            "provenance.source",
            "provenance.publication",
            "provenance.retrieved",
            "provenance.checksum",
        ] {
            if self.string(key).is_err() {
                missing.push(key);
            }
        }
        if missing.is_empty() {
            Finding::ok(
                "provenance",
                format!(
                    "{} p{} retrieved {}, {}",
                    self.string("provenance.publication").unwrap_or_default(),
                    self.integer("provenance.page").unwrap_or(0),
                    self.string("provenance.retrieved").unwrap_or_default(),
                    self.string("provenance.checksum").unwrap_or_default()
                ),
            )
        } else {
            Finding::fail(
                "provenance",
                format!(
                    "claims to be measured without {} — it is a placeholder until they are filled in",
                    missing.join(", ")
                ),
            )
        }
    }

    /// The three layers, and the fit against the points when they are named.
    fn check_curves(&self) -> Vec<Finding> {
        let mut findings = Vec::new();
        let base = if self.is_film() {
            self.floats("base.density").ok().filter(|v| v.len() == 3)
        } else {
            None
        };
        for (index, layer) in ["red", "green", "blue"].into_iter().enumerate() {
            let prefix = format!("curve.{layer}");
            let curve = match self.curve(&prefix) {
                Ok(curve) => curve,
                Err(error) => {
                    findings.push(Finding::fail(layer, error.to_string()));
                    continue;
                }
            };
            // A negative's density rises with exposure and a reversal's falls,
            // so which end is which depends on the process — the one place the
            // curve's two numbers are not interchangeable.
            if self.is_reversal() {
                if curve.d_min <= curve.d_max {
                    findings.push(Finding::fail(
                        layer,
                        format!(
                            "d_min {} is not above d_max {} — a reversal starts at its \
                             maximum density on unexposed film and clears as the image forms",
                            curve.d_min, curve.d_max
                        ),
                    ));
                    continue;
                }
            } else if curve.d_min >= curve.d_max {
                findings.push(Finding::fail(
                    layer,
                    format!("d_min {} is not below d_max {}", curve.d_min, curve.d_max),
                ));
                continue;
            }
            if curve.gamma <= 0.0 {
                findings.push(Finding::fail(
                    layer,
                    format!("gamma {} is not positive", curve.gamma),
                ));
                continue;
            }
            // The renderer adds `base.density` to the curve, so a film's curve
            // is dye above base and its d_min is zero. A file that puts the base
            // in both places would render the film twice as dense as it is.
            if self.is_film() && !self.is_reversal() && curve.d_min.abs() > 1e-9 {
                findings.push(Finding::fail(
                    layer,
                    format!(
                        "d_min {} — a film's curve is dye above base, so d_min is 0 and \
                         `base.density` carries the rest",
                        curve.d_min
                    ),
                ));
                continue;
            }
            // A reversal's curve is total density, base included, so there is
            // nothing to add back before comparing it with the sheet's points.
            let base_for_fit = if self.is_reversal() {
                None
            } else {
                base.as_ref().map(|b| b[index])
            };
            match self.check_fit(&prefix, &curve, base_for_fit) {
                Ok(text) => findings.push(Finding::ok(layer, text)),
                Err(error) => findings.push(Finding::fail(layer, error.to_string())),
            }
        }
        findings
    }

    /// Re-derive the fit from the named points and compare with the file's rms.
    ///
    /// `base` is this layer's base density when the stock is a film. The model's
    /// film curve is dye above base, but a data sheet plots total density, so
    /// the base is added back before the comparison — which is also what makes
    /// `base.density` a checked number rather than a comment.
    fn check_fit(
        &self,
        prefix: &str,
        curve: &CharacteristicCurve,
        base: Option<f64>,
    ) -> Result<String, StockError> {
        let Ok(points) = self.string(&format!("{prefix}.points")) else {
            return Ok("no digitised points named; the curve is taken on trust".to_owned());
        };
        let path = self.path.parent().unwrap_or(Path::new(".")).join(&points);
        let rows = read_points(&path)?;
        if rows.len() < 20 {
            return Err(StockError::Check {
                path: self.path.clone(),
                stage: prefix.to_owned(),
                message: format!(
                    "{} has {} points, which is not a digitised curve",
                    path.display(),
                    rows.len()
                ),
            });
        }
        let scale = self
            .string(&format!("{prefix}.x_scale"))
            .unwrap_or_else(|_| "log_exposure".to_owned());
        let factor = if scale == "camera_stops" {
            std::f64::consts::LOG10_2
        } else {
            1.0
        };
        let mut sum = 0.0;
        let offset = base.unwrap_or(0.0);
        for (x, density) in &rows {
            let model = curve.density(x * factor) + offset;
            sum += (model - density) * (model - density);
        }
        let rms = (sum / rows.len() as f64).sqrt();
        let declared = self.float(&format!("{prefix}.rms")).ok();
        match declared {
            Some(declared) if declared > 0.1 => Err(StockError::Check {
                path: self.path.clone(),
                stage: prefix.to_owned(),
                message: format!(
                    "declares an rms of {declared:.3}; a curve fitted to a digitised sheet \
                     lands under 0.05, so that number would excuse anything"
                ),
            }),
            // Ten per cent: the fit's own uncertainty. What this catches is a
            // transposed decimal, a dropped minus or a swapped layer — not a
            // digit in the third place, which the data does not resolve either.
            Some(declared) if rms <= declared * 1.10 => Ok(format!(
                "{} points, rms {rms:.4} against a declared {declared:.4}",
                rows.len()
            )),
            Some(declared) => Err(StockError::Check {
                path: self.path.clone(),
                stage: prefix.to_owned(),
                message: format!(
                    "rms {rms:.4} against the declared {declared:.4} — the curve does not \
                     reproduce the points it names, so one of the two is wrong"
                ),
            }),
            None => Err(StockError::Check {
                path: self.path.clone(),
                stage: prefix.to_owned(),
                message: format!(
                    "names points but no `rms`; the fit's residual is {rms:.4} and cannot be \
                     checked against anything"
                ),
            }),
        }
    }

    /// The per-stock numbers that are not on the curve.
    fn check_base(&self) -> Finding {
        if self.is_film() {
            match (
                self.floats("base.density"),
                self.floats("base.grains_per_um2"),
            ) {
                (Ok(density), Ok(grains)) if density.len() == 3 && grains.len() == 3 => {
                    Finding::ok(
                        "base",
                        format!("status density {density:?}, grains {grains:?} per µm²"),
                    )
                }
                _ => Finding::fail(
                    "base",
                    "a film needs `base.density` and `base.grains_per_um2`, three values each",
                ),
            }
        } else {
            match self.float("base.target_mid_reflectance") {
                Ok(value) if (0.01..=1.0).contains(&value) => {
                    Finding::ok("base", format!("target mid reflectance {value:.3}"))
                }
                Ok(value) => Finding::fail(
                    "base",
                    format!("target_mid_reflectance {value} is not a reflectance"),
                ),
                Err(_) => Finding::fail("base", "a paper needs `base.target_mid_reflectance`"),
            }
        }
    }

    /// The chemistry the stock declares, and whether its blocks can serve it.
    ///
    /// The requirement comes from the process, not from the checker's taste: a
    /// reversal film is the picture and needs its own dyes, a monochrome film
    /// has no dyes to give, and a negative borrows them when the sheet does not
    /// print them.
    fn check_process(&self) -> Finding {
        let process = self
            .string("stock.process")
            .unwrap_or_else(|_| "negative".to_owned());
        let dyes = self
            .strings("spectra.dyes")
            .map(|d| !d.is_empty())
            .unwrap_or(false);
        match process.as_str() {
            "negative" => Finding::ok(
                "process",
                if dyes {
                    "negative, dyes on the sheet".to_owned()
                } else {
                    "negative, dyes borrowed".to_owned()
                },
            ),
            "reversal" if dyes => {
                Finding::ok("reversal", "dyes are its own, and there is no print")
            }
            "reversal" => Finding::fail(
                "reversal",
                "a reversal film is its own picture: it needs `spectra.dyes`",
            ),
            "monochrome" if dyes => Finding::fail(
                "monochrome",
                "a silver film has no dyes; a chromogenic one needs a process this format lacks",
            ),
            "monochrome" => Finding::ok("monochrome", "one record, no dyes, no mask"),
            other => Finding::fail(
                "process",
                format!("{other:?} is not negative, reversal or monochrome"),
            ),
        }
    }

    /// Which quantities the stock takes from another one, if any.
    ///
    /// A manufacturer sheet does not always publish every quantity the model
    /// wants: Kodak's still films print a neutral subject and D-min rather than
    /// three dyes. Borrowing is legitimate; borrowing silently is not. A stock
    /// that declares a borrow can still claim to be measured, and the check
    /// says what was taken.
    fn check_borrowed(&self) -> Finding {
        match self.strings("stock.borrowed") {
            Ok(names) if names.is_empty() => {
                Finding::note("borrowed", "nothing; every quantity is this sheet's")
            }
            Ok(names) => Finding::ok("borrowed", format!("{:?} from the compiled stock", names)),
            Err(_) => Finding::note("borrowed", "nothing declared"),
        }
    }

    /// The emulsion's blur, if the sheet publishes an MTF.
    ///
    /// Optional: a stock without a measured modulation-transfer curve is a
    /// stock that borrows the blur, and saying so is better than inventing a
    /// sigma. When present, three positive finite values in micrometres.
    fn check_emulsion(&self) -> Finding {
        if !self.is_film() {
            return Finding::note("emulsion", "not a film");
        }
        let Ok(sigma) = self.floats("emulsion.sigma_um") else {
            return Finding::note(
                "emulsion",
                "no `emulsion.sigma_um`; the stock falls back to the compiled blur",
            );
        };
        if sigma.len() == 3 && sigma.iter().all(|s| s.is_finite() && *s > 0.0) {
            Finding::ok(
                "emulsion",
                format!("sigma {:?} µm, measured from the sheet's MTF", sigma),
            )
        } else {
            Finding::fail(
                "emulsion",
                "`emulsion.sigma_um` must be three positive finite numbers",
            )
        }
    }

    /// The spectra, on the grid the model integrates over.
    fn check_spectra(&self) -> Vec<Finding> {
        let mut findings = Vec::new();
        for section in ["spectra.dyes", "spectra.layers"] {
            let Ok(paths) = self.strings(section) else {
                findings.push(Finding::note(
                    section,
                    "not given; the stock falls back to the placeholder spectra",
                ));
                continue;
            };
            if paths.len() != 3 {
                findings.push(Finding::fail(
                    section,
                    format!("{} files; a paper or film has three layers", paths.len()),
                ));
                continue;
            }
            let mut problems = Vec::new();
            for name in &paths {
                let path = self.path.parent().unwrap_or(Path::new(".")).join(name);
                match check_spectrum(&path) {
                    Ok(peak) => findings.push(Finding::ok(
                        section,
                        format!("{}: 71 samples on the grid, peak {peak:.3}", path.display()),
                    )),
                    Err(message) => problems.push(format!("{}: {message}", path.display())),
                }
            }
            if !problems.is_empty() {
                findings.push(Finding::fail(section, problems.join("; ")));
            }
        }
        findings
    }

    // ---------------------------------------------------------------- access

    fn require(&self, keys: &[&str]) -> Result<(), StockError> {
        for key in keys {
            if !self.table.contains_key(*key) {
                return Err(self.fail(format!("missing required field `{key}`")));
            }
        }
        Ok(())
    }

    fn fail(&self, message: String) -> StockError {
        StockError::Check {
            path: self.path.clone(),
            stage: "parse".to_owned(),
            message,
        }
    }

    fn string(&self, key: &str) -> Result<String, StockError> {
        match self.table.get(key) {
            Some(Value::String(value)) => Ok(value.clone()),
            Some(_) => Err(self.fail(format!("`{key}` is not a string"))),
            None => Err(self.fail(format!("missing `{key}`"))),
        }
    }

    fn float(&self, key: &str) -> Result<f64, StockError> {
        match self.table.get(key) {
            Some(Value::Number(value)) => Ok(*value),
            Some(_) => Err(self.fail(format!("`{key}` is not a number"))),
            None => Err(self.fail(format!("missing `{key}`"))),
        }
    }

    fn integer(&self, key: &str) -> Result<u32, StockError> {
        self.float(key).map(|value| value.max(0.0) as u32)
    }

    fn floats(&self, key: &str) -> Result<Vec<f64>, StockError> {
        match self.table.get(key) {
            Some(Value::List(values)) => values
                .iter()
                .map(|value| match value {
                    Value::Number(number) => Ok(*number),
                    _ => Err(self.fail(format!("`{key}` has a non-numeric entry"))),
                })
                .collect(),
            Some(_) => Err(self.fail(format!("`{key}` is not a list"))),
            None => Err(self.fail(format!("missing `{key}`"))),
        }
    }

    fn strings(&self, key: &str) -> Result<Vec<String>, StockError> {
        match self.table.get(key) {
            Some(Value::List(values)) => values
                .iter()
                .map(|value| match value {
                    Value::String(text) => Ok(text.clone()),
                    _ => Err(self.fail(format!("`{key}` has a non-string entry"))),
                })
                .collect(),
            Some(_) => Err(self.fail(format!("`{key}` is not a list"))),
            None => Err(self.fail(format!("missing `{key}`"))),
        }
    }

    fn curve(&self, prefix: &str) -> Result<CharacteristicCurve, StockError> {
        let base = CharacteristicCurve::new(
            self.float(&format!("{prefix}.d_min"))?,
            self.float(&format!("{prefix}.d_max"))?,
            self.float(&format!("{prefix}.gamma"))?,
            self.float(&format!("{prefix}.log_e0"))?,
        );
        Ok(match self.float(&format!("{prefix}.transition")) {
            Ok(transition) if transition > 0.0 => base.with_transition(transition),
            Ok(transition) => {
                return Err(self.fail(format!(
                    "{prefix}.transition is {transition}, which is not a transition"
                )));
            }
            Err(_) => base,
        })
    }
}

/// One line of the checker's report.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Finding {
    /// Which part of the stock it is about.
    pub stage: String,
    /// How it went.
    pub verdict: Verdict,
    /// What it found.
    pub message: String,
}

/// How a check went.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Verdict {
    /// Fine.
    Ok,
    /// Worth knowing, not a problem.
    Note,
    /// The stock is not usable as it stands.
    Fail,
}

impl Finding {
    fn ok(stage: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            stage: stage.into(),
            verdict: Verdict::Ok,
            message: message.into(),
        }
    }
    fn note(stage: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            stage: stage.into(),
            verdict: Verdict::Note,
            message: message.into(),
        }
    }
    fn fail(stage: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            stage: stage.into(),
            verdict: Verdict::Fail,
            message: message.into(),
        }
    }
}

impl fmt::Display for Finding {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let mark = match self.verdict {
            Verdict::Ok => "ok  ",
            Verdict::Note => "note",
            Verdict::Fail => "FAIL",
        };
        write!(formatter, "  {mark}  {:<10} {}", self.stage, self.message)
    }
}

/// What can go wrong reading a stock file.
#[derive(Debug)]
pub enum StockError {
    /// The file could not be read.
    Io {
        /// Path that failed.
        path: PathBuf,
        /// The OS error.
        source: std::io::Error,
    },
    /// A syntax error, with the line it was on.
    Syntax {
        /// Path that failed.
        path: PathBuf,
        /// One-based line number.
        line: usize,
        /// What the parser expected.
        message: String,
    },
    /// A field that is missing, malformed or inconsistent.
    Check {
        /// Path that failed.
        path: PathBuf,
        /// Which part of the stock.
        stage: String,
        /// What was wrong.
        message: String,
    },
}

impl fmt::Display for StockError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io { path, source } => write!(formatter, "{}: {source}", path.display()),
            Self::Syntax {
                path,
                line,
                message,
            } => {
                write!(formatter, "{}:{line}: {message}", path.display())
            }
            Self::Check {
                path,
                stage,
                message,
            } => {
                write!(formatter, "{} [{stage}]: {message}", path.display())
            }
        }
    }
}

impl std::error::Error for StockError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io { source, .. } => Some(source),
            _ => None,
        }
    }
}

// ------------------------------------------------------------------ parsing

/// A value in a stock file.
#[derive(Debug, Clone, PartialEq)]
enum Value {
    String(String),
    Number(f64),
    List(Vec<Value>),
}

fn parse(text: &str, path: &Path) -> Result<BTreeMap<String, Value>, StockError> {
    let mut table = BTreeMap::new();
    let mut section = String::new();
    let lines: Vec<&str> = text.lines().collect();
    let mut index = 0;
    while index < lines.len() {
        let raw = lines[index];
        let line = index + 1;
        let trimmed = raw.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            index += 1;
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix('[') {
            let Some(name) = rest.strip_suffix(']') else {
                return Err(StockError::Syntax {
                    path: path.to_path_buf(),
                    line,
                    message: "a section header ends with `]`".to_owned(),
                });
            };
            section = name.trim().to_owned();
            index += 1;
            continue;
        }
        let Some((key, value)) = trimmed.split_once('=') else {
            return Err(StockError::Syntax {
                path: path.to_path_buf(),
                line,
                message: "expected `key = value` or `[section]`".to_owned(),
            });
        };
        let key = key.trim();
        let full = if section.is_empty() {
            key.to_owned()
        } else {
            format!("{section}.{key}")
        };
        // A list may span lines; everything else is one line, which is what
        // keeps the parser this small.
        let mut literal = value.trim().to_owned();
        while literal.starts_with('[') && !literal.contains(']') {
            index += 1;
            let Some(next) = lines.get(index) else {
                return Err(StockError::Syntax {
                    path: path.to_path_buf(),
                    line,
                    message: "a list is not closed with `]`".to_owned(),
                });
            };
            literal.push(' ');
            literal.push_str(next.trim());
        }
        let parsed = parse_value(&literal).map_err(|message| StockError::Syntax {
            path: path.to_path_buf(),
            line,
            message,
        })?;
        table.insert(full, parsed);
        index += 1;
    }
    Ok(table)
}

fn parse_value(text: &str) -> Result<Value, String> {
    let text = text.trim();
    if let Some(rest) = text.strip_prefix('"') {
        let Some(end) = rest.find('"') else {
            return Err("a string ends with `\"`".to_owned());
        };
        let trailing = rest[end + 1..].trim();
        if !trailing.is_empty() && !trailing.starts_with('#') {
            return Err(format!("unexpected {trailing:?} after a string"));
        }
        return Ok(Value::String(rest[..end].to_owned()));
    }
    if let Some(rest) = text.strip_prefix('[') {
        let Some(end) = rest.find(']') else {
            return Err("a list ends with `]`".to_owned());
        };
        let mut values = Vec::new();
        for item in rest[..end].split(',') {
            let item = item.trim();
            if item.is_empty() {
                continue;
            }
            values.push(parse_value(item)?);
        }
        return Ok(Value::List(values));
    }
    // Strip a trailing comment from a bare number.
    let bare = text.split('#').next().unwrap_or(text).trim();
    bare.parse::<f64>()
        .map(Value::Number)
        .map_err(|_| format!("{bare:?} is not a number or a quoted string"))
}

// -------------------------------------------------------------------- files

fn read_points(path: &Path) -> Result<Vec<(f64, f64)>, StockError> {
    let text = std::fs::read_to_string(path).map_err(|source| StockError::Io {
        path: path.to_path_buf(),
        source,
    })?;
    let mut rows = Vec::new();
    for line in text.lines().skip(1) {
        let mut fields = line.split(',');
        let (Some(x), Some(y)) = (fields.next(), fields.next()) else {
            continue;
        };
        let (Ok(x), Ok(y)) = (x.trim().parse::<f64>(), y.trim().parse::<f64>()) else {
            continue;
        };
        rows.push((x, y));
    }
    Ok(rows)
}

/// Check one spectrum file is on the model's grid, and return its peak.
fn check_spectrum(path: &Path) -> Result<f64, String> {
    let set = kallotype_spectral::load_csv(path).map_err(|error| error.to_string())?;
    if set.samples.is_empty() {
        return Err("no columns".to_owned());
    }
    let grid = &set.grid;
    if grid.values().len() != 71 {
        return Err(format!("{} samples, not 71", grid.values().len()));
    }
    if (grid.start_nm() - 380.0).abs() > 1e-9 || (grid.step_nm() - 5.0).abs() > 1e-9 {
        return Err(format!(
            "starts at {} nm in {} nm steps, not 380 in 5",
            grid.start_nm(),
            grid.step_nm()
        ));
    }
    let mut peak: f64 = 0.0;
    for value in set.samples[0].reflectance.values() {
        if !value.is_finite() || *value < 0.0 {
            return Err(format!("value {value} is not a non-negative number"));
        }
        peak = peak.max(*value);
    }
    Ok(peak)
}

#[cfg(test)]
mod tests {
    use super::*;

    const EXAMPLE: &str = r#"
# A stock, as data.
[stock]
id = "example"          # comment after a value
label = "An example paper"
kind = "paper"
claim = "measured"

[provenance]
source = "A data sheet"
publication = "E-0000"
page = 7
retrieved = "2026-11-07"
checksum = "sha256:0000"

[curve.red]
d_min = 0.10
d_max = 2.50
gamma = 3.5
log_e0 = -1.40
transition = 7.0

[curve.green]
d_min = 0.10
d_max = 2.50
gamma = 3.5
log_e0 = -1.40

[curve.blue]
d_min = 0.12
d_max = 2.40
gamma = 4.0
log_e0 = -1.42

[base]
target_mid_reflectance = 0.18
"#;

    fn parsed() -> StockFile {
        let table = parse(EXAMPLE, Path::new("example.toml")).expect("parses");
        StockFile {
            path: PathBuf::from("example.toml"),
            table,
        }
    }

    #[test]
    fn the_subset_parses() {
        let file = parsed();
        assert_eq!(file.id(), "example");
        assert_eq!(file.label(), "An example paper");
        assert!(!file.is_film());
        assert!(file.claims_measured());
        assert_eq!(file.float("curve.red.gamma").unwrap(), 3.5);
        // A missing transition falls back to the negative's default.
        let curve = file.curve("curve.green").expect("green");
        assert_eq!(curve.transition, kallotype_core::curve::TRANSITION);
        // And one that is given is kept.
        assert_eq!(file.curve("curve.red").unwrap().transition, 7.0);
    }

    #[test]
    fn a_comment_does_not_join_the_value() {
        let file = parsed();
        assert_eq!(file.string("stock.id").unwrap(), "example");
    }

    #[test]
    fn a_measured_stock_without_a_document_fails() {
        let text = EXAMPLE.replace("checksum = \"sha256:0000\"\n", "");
        let table = parse(&text, Path::new("t.toml")).expect("parses");
        let file = StockFile {
            path: PathBuf::from("t.toml"),
            table,
        };
        let finding = file.check_provenance();
        assert_eq!(finding.verdict, Verdict::Fail);
        assert!(
            finding.message.contains("provenance.checksum"),
            "{}",
            finding.message
        );
    }

    #[test]
    fn a_placeholder_says_so_and_passes() {
        let text = EXAMPLE
            .replace("claim = \"measured\"", "claim = \"placeholder\"")
            .replace("checksum = \"sha256:0000\"\n", "");
        let table = parse(&text, Path::new("t.toml")).expect("parses");
        let file = StockFile {
            path: PathBuf::from("t.toml"),
            table,
        };
        let finding = file.check_provenance();
        assert_eq!(finding.verdict, Verdict::Note);
    }

    #[test]
    fn a_curve_that_is_not_a_curve_fails() {
        let text = EXAMPLE.replace("d_min = 0.10", "d_min = 3.0");
        let table = parse(&text, Path::new("t.toml")).expect("parses");
        let file = StockFile {
            path: PathBuf::from("t.toml"),
            table,
        };
        let findings = file.check_curves();
        assert!(
            findings.iter().any(|f| f.verdict == Verdict::Fail),
            "{findings:?}"
        );
    }

    #[test]
    fn a_paper_needs_its_target_and_a_film_its_grain() {
        let file = parsed();
        assert_eq!(file.check_base().verdict, Verdict::Ok);
        let text = EXAMPLE.replace("kind = \"paper\"", "kind = \"film\"");
        let table = parse(&text, Path::new("t.toml")).expect("parses");
        let film = StockFile {
            path: PathBuf::from("t.toml"),
            table,
        };
        assert_eq!(film.check_base().verdict, Verdict::Fail);
    }

    #[test]
    fn a_syntax_error_names_its_line() {
        let error = parse(
            "[stock]\nid = \"x\"\nthis is not a pair\n",
            Path::new("t.toml"),
        )
        .expect_err("a line that is not a pair fails");
        let text = error.to_string();
        assert!(text.contains(":3:"), "{text}");
    }

    #[test]
    fn a_number_and_a_string_are_not_confused() {
        let table = parse("[a]\nb = 1\nc = \"2\"\n", Path::new("t.toml")).expect("parses");
        let file = StockFile {
            path: PathBuf::from("t.toml"),
            table,
        };
        assert!(file.float("a.b").is_ok());
        assert!(file.float("a.c").is_err());
        assert!(file.string("a.c").is_ok());
        assert!(file.string("a.b").is_err());
    }

    #[test]
    fn a_film_may_not_carry_its_base_in_the_curve() {
        let text = EXAMPLE.replace("kind = \"paper\"", "kind = \"film\"");
        let table = parse(&text, Path::new("t.toml")).expect("parses");
        let file = StockFile {
            path: PathBuf::from("t.toml"),
            table,
        };
        let findings = file.check_curves();
        assert!(
            findings
                .iter()
                .any(|f| f.verdict == Verdict::Fail && f.message.contains("dye above base")),
            "{findings:?}"
        );
    }

    /// A data sheet plots base plus dye; the model's curve is dye alone, so the
    /// points are only reproduced once `base.density` is added back. This is the
    /// check that makes those three numbers mean something.
    #[test]
    fn a_films_points_are_base_plus_dye() {
        let root = std::env::temp_dir().join(format!("kallotype-stock-{}", std::process::id()));
        std::fs::create_dir_all(&root).expect("a temporary directory");
        let layers = ["red", "green", "blue"];
        let curves = [
            CharacteristicCurve::new(0.0, 1.70, 0.48, -0.76),
            CharacteristicCurve::new(0.0, 2.00, 0.56, -0.73),
            CharacteristicCurve::new(0.0, 1.92, 0.55, -0.75),
        ];
        let base = [0.19, 0.58, 0.83];

        let text = |base: [f64; 3]| {
            let mut text = String::from(
                "[stock]\nid = \"test_film\"\nlabel = \"A film\"\nkind = \"film\"\n\
                 claim = \"placeholder\"\n",
            );
            for (index, layer) in layers.iter().enumerate() {
                let name = format!("{layer}.csv");
                let mut csv = String::from("log_exposure,density\n");
                let mut x = -4.0;
                while x <= 1.0 {
                    let density = curves[index].density(x) + base[index];
                    csv.push_str(&format!("{x:.3},{density:.4}\n"));
                    x += 0.02;
                }
                std::fs::write(root.join(&name), csv).expect("a points file");
                let curve = &curves[index];
                text.push_str(&format!(
                    "\n[curve.{layer}]\nd_min = {:.4}\nd_max = {:.4}\ngamma = {:.4}\n\
                     log_e0 = {:.4}\npoints = \"{name}\"\nrms = 0.001\n",
                    curve.d_min, curve.d_max, curve.gamma, curve.log_e0
                ));
            }
            text.push_str(&format!(
                "\n[base]\ndensity = [{}, {}, {}]\ngrains_per_um2 = [1.0, 1.0, 1.0]\n",
                base[0], base[1], base[2]
            ));
            text
        };

        let written = text(base);
        let right = root.join("right.toml");
        std::fs::write(&right, &written).expect("a stock file");
        let findings = StockFile::read(&right).expect("reads").check_curves();
        assert!(
            findings.iter().all(|f| f.verdict == Verdict::Ok),
            "{findings:?}"
        );

        // The same points, with the base declared a tenth higher: the curve no
        // longer reaches the sheet's numbers, and the check has to say so.
        let wrong = root.join("wrong.toml");
        std::fs::write(
            &wrong,
            written.replace(
                "density = [0.19, 0.58, 0.83]",
                "density = [0.29, 0.58, 0.83]",
            ),
        )
        .expect("a stock file");
        let findings = StockFile::read(&wrong).expect("reads").check_curves();
        assert!(
            findings
                .iter()
                .any(|f| f.verdict == Verdict::Fail && f.message.contains("rms")),
            "{findings:?}"
        );
        std::fs::remove_dir_all(&root).expect("clean up");
    }
}
