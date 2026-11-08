//! Reading a `.kalofilm` file — the format in `films/FORMAT.md`.
//!
//! A film is data: a header that says where every number came from, the spectra
//! as a contiguous block of little-endian f64, and a SHA-256 over the lot. This
//! module turns that into a [`FilmStock`] the renderer already knows how to
//! use, so a film can be added without recompiling.
//!
//! The tables are **leaked** rather than owned. `FilmStock` describes its
//! spectra with `&'static` slices because every stock before this one was a
//! compile-time constant, and threading an owner through `RenderParams`, the
//! pipeline and both backends would be a large change to buy a few kilobytes
//! that a process holds until it exits anyway. A caller that loads films in a
//! loop should use [`read_owned`] instead, which returns the boxed stock.
//!
//! ## Why the digest is checked by hand
//!
//! The alternative is a dependency on a hash crate for sixty lines of a
//! standard algorithm. This crate has one dependency (`clap`) and a `cargo deny`
//! gate; the vectors below are FIPS 180-2's.

use std::path::Path;

use kallotype_core::CharacteristicCurve;
use kallotype_core::dye::InhibitorLayer;
use kallotype_core::emulsion::{FilmProcess, FilmStock};

use crate::stockfile::{Value, parse};

/// Every table in version 1 is this many points on a 5 nm grid.
const GRID_LEN: usize = 71;
const MAGIC: &[u8; 8] = b"KALOFILM";

/// What can go wrong reading a film file.
#[derive(Debug)]
pub enum FilmFileError {
    /// The file could not be read.
    Io(std::io::Error),
    /// It is not a film file, or not this version of one.
    Format(String),
    /// The digest does not cover the bytes, so the file is truncated or altered.
    Digest {
        /// The digest stored in the file.
        expected: String,
        /// The digest of the bytes that are actually there.
        found: String,
    },
    /// The header parses but does not describe a film this build understands.
    Header(String),
}

impl std::fmt::Display for FilmFileError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(error) => write!(formatter, "{error}"),
            Self::Format(message) => write!(formatter, "{message}"),
            Self::Digest { expected, found } => write!(
                formatter,
                "digest mismatch: the file says {expected}, the bytes hash to {found}"
            ),
            Self::Header(message) => write!(formatter, "{message}"),
        }
    }
}

impl std::error::Error for FilmFileError {}

impl From<std::io::Error> for FilmFileError {
    fn from(error: std::io::Error) -> Self {
        Self::Io(error)
    }
}

/// Load a film, leaking its tables so the renderer can borrow them.
pub fn read(path: impl AsRef<Path>) -> Result<&'static FilmStock, FilmFileError> {
    read_owned(path).map(|stock| &*Box::leak(stock))
}

/// Load a film as an owned value, for a caller that loads many.
pub fn read_owned(path: impl AsRef<Path>) -> Result<Box<FilmStock>, FilmFileError> {
    let bytes = std::fs::read(path.as_ref())?;
    if bytes.len() < 48 || &bytes[..8] != MAGIC {
        return Err(FilmFileError::Format(
            "not a kalofilm file (no KALOFILM magic)".to_owned(),
        ));
    }
    let version = u32::from_le_bytes(bytes[8..12].try_into().expect("four bytes"));
    if version != 1 {
        return Err(FilmFileError::Format(format!(
            "version {version}; this build reads version 1"
        )));
    }
    let header_len = u32::from_le_bytes(bytes[12..16].try_into().expect("four bytes")) as usize;
    let header_end = 16usize
        .checked_add(header_len)
        .filter(|end| *end + 32 <= bytes.len())
        .ok_or_else(|| FilmFileError::Format("the header runs past the file".to_owned()))?;

    let found = sha256(&bytes[..bytes.len() - 32]);
    if found != bytes[bytes.len() - 32..] {
        return Err(FilmFileError::Digest {
            expected: hex(&bytes[bytes.len() - 32..]),
            found: hex(&found),
        });
    }

    let text = std::str::from_utf8(&bytes[16..header_end])
        .map_err(|_| FilmFileError::Format("the header is not UTF-8".to_owned()))?;
    let table = parse(text, Path::new("<film>"))
        .map_err(|error| FilmFileError::Header(format!("the header does not parse: {error}")))?;
    let tables = &bytes[header_end..bytes.len() - 32];

    build(&table, tables)
}

fn string(
    table: &std::collections::BTreeMap<String, Value>,
    key: &str,
) -> Result<String, FilmFileError> {
    match table.get(key) {
        Some(Value::String(value)) => Ok(value.clone()),
        _ => Err(FilmFileError::Header(format!("`{key}` is missing"))),
    }
}

fn number(
    table: &std::collections::BTreeMap<String, Value>,
    key: &str,
) -> Result<f64, FilmFileError> {
    match table.get(key) {
        Some(Value::Number(value)) => Ok(*value),
        _ => Err(FilmFileError::Header(format!("`{key}` is missing"))),
    }
}

fn numbers(
    table: &std::collections::BTreeMap<String, Value>,
    key: &str,
) -> Result<Vec<f64>, FilmFileError> {
    match table.get(key) {
        Some(Value::List(items)) => items
            .iter()
            .map(|item| match item {
                Value::Number(value) => Ok(*value),
                _ => Err(FilmFileError::Header(format!("`{key}` is not all numbers"))),
            })
            .collect(),
        _ => Err(FilmFileError::Header(format!("`{key}` is missing"))),
    }
}

fn grid(slice: &[f64]) -> Result<[f64; GRID_LEN], FilmFileError> {
    slice
        .try_into()
        .map_err(|_| FilmFileError::Format(format!("a table is not {GRID_LEN} points")))
}

fn build(
    table: &std::collections::BTreeMap<String, Value>,
    tables: &[u8],
) -> Result<Box<FilmStock>, FilmFileError> {
    let schema = string(table, "schema")?;
    if schema != "film/v1" {
        return Err(FilmFileError::Format(format!("schema `{schema}`")));
    }
    let process = match string(table, "process")?.as_str() {
        "negative" => FilmProcess::Negative,
        "reversal" => FilmProcess::Reversal,
        "monochrome" => FilmProcess::Monochrome,
        other => return Err(FilmFileError::Header(format!("unknown process `{other}`"))),
    };

    let names = strings(table, "tables")?;
    let mut at = 0usize;
    let mut layers = None;
    let mut dyes = None;
    let mut mask = None;
    let mut cl_layer = None;
    for name in &names {
        let rows = match name.as_str() {
            "layers" | "dyes" => 3,
            "mask" | "cl_sensitivity" => 1,
            other => {
                return Err(FilmFileError::Format(format!("unknown table `{other}`")));
            }
        };
        let values = read_table(tables, &mut at, rows)?;
        match name.as_str() {
            "layers" => layers = Some(leak_three(values)),
            "dyes" => dyes = Some(leak_three(values)),
            "mask" => mask = Some(leak_one(&values[0])),
            "cl_sensitivity" => {
                cl_layer = Some(InhibitorLayer {
                    sensitivity: leak_one(&values[0]),
                });
            }
            _ => unreachable!("the name was matched above"),
        }
    }

    let channel = |name: &str| -> Result<CharacteristicCurve, FilmFileError> {
        let curve = |key: &str| number(table, &format!("curve.{name}.{key}"));
        let base = CharacteristicCurve::new(
            curve("d_min")?,
            curve("d_max")?,
            curve("gamma")?,
            curve("log_e0")?,
        )
        .with_transition(curve("transition")?);
        // A file written before the two corners could differ has no second
        // rate, and its one number is still the right answer for both.
        let toe = curve("toe_transition").unwrap_or(base.toe_transition);
        let shoulder = curve("shoulder_transition").unwrap_or(base.shoulder_transition);
        Ok(base.with_corners(toe, shoulder))
    };
    let sigma = numbers(table, "character.sigma_um")?;
    Ok(Box::new(FilmStock {
        id: leak_str(string(table, "id")?),
        process,
        extra_cyan: None,
        cl_layer,
        label: leak_str(string(table, "label")?),
        note: leak_str(string(table, "provenance.note")?),
        channels: [channel("red")?, channel("green")?, channel("blue")?],
        base_density: numbers(table, "character.base_density")?
            .try_into()
            .map_err(|_| FilmFileError::Header("`base_density` needs three numbers".to_owned()))?,
        grains_per_um2: numbers(table, "character.grains_per_um2")?
            .try_into()
            .map_err(|_| {
                FilmFileError::Header("`grains_per_um2` needs three numbers".to_owned())
            })?,
        layers: layers.ok_or_else(|| FilmFileError::Header("no `layers` table".to_owned()))?,
        // A v1 file must carry the dyes: a renderer cannot print a film whose
        // primaries are zeros, and borrowing another film's would be a fact
        // the file did not state.
        dyes: dyes.ok_or_else(|| FilmFileError::Header("no `dyes` table".to_owned()))?,
        // A reversal has no orange mask, and a missing table is how the format
        // says so.
        mask: mask.unwrap_or_else(|| Box::leak(Box::new([0.0; GRID_LEN]))),
        sigma_um: sigma
            .iter()
            .any(|value| *value > 0.0)
            .then(|| sigma.try_into().ok())
            .flatten(),
        reference_time_min: number(table, "development.reference_time_min").unwrap_or(6.5),
        reference_temp_c: number(table, "development.reference_temp_c").unwrap_or(20.0),
    }))
}

fn strings(
    table: &std::collections::BTreeMap<String, Value>,
    key: &str,
) -> Result<Vec<String>, FilmFileError> {
    match table.get(key) {
        Some(Value::List(items)) => items
            .iter()
            .map(|item| match item {
                Value::String(value) => Ok(value.clone()),
                _ => Err(FilmFileError::Header(format!("`{key}` is not all strings"))),
            })
            .collect(),
        _ => Err(FilmFileError::Header(format!("`{key}` is missing"))),
    }
}

fn read_table(
    tables: &[u8],
    at: &mut usize,
    rows: usize,
) -> Result<Vec<[f64; GRID_LEN]>, FilmFileError> {
    let bytes = rows * GRID_LEN * 8;
    let slice = tables.get(*at..*at + bytes).ok_or_else(|| {
        FilmFileError::Format(format!("a table of {rows} rows runs past the file"))
    })?;
    *at += bytes;
    slice
        .chunks_exact(GRID_LEN * 8)
        .map(|row| {
            let values: Vec<f64> = row
                .chunks_exact(8)
                .map(|chunk| f64::from_le_bytes(chunk.try_into().expect("eight bytes")))
                .collect();
            grid(&values)
        })
        .collect()
}

fn leak_three(values: Vec<[f64; GRID_LEN]>) -> &'static [[f64; GRID_LEN]; 3] {
    Box::leak(Box::new(
        values.try_into().expect("three rows were requested"),
    ))
}

fn leak_one(values: &[f64; GRID_LEN]) -> &'static [f64; GRID_LEN] {
    Box::leak(Box::new(*values))
}

fn leak_str(value: String) -> &'static str {
    Box::leak(value.into_boxed_str())
}

// ---------------------------------------------------------------- SHA-256

const K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

/// SHA-256 of a byte slice, as thirty-two bytes.
#[must_use]
pub fn sha256(data: &[u8]) -> [u8; 32] {
    let mut state: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];
    let mut message = data.to_vec();
    let bits = (data.len() as u64) * 8;
    message.push(0x80);
    while message.len() % 64 != 56 {
        message.push(0);
    }
    message.extend_from_slice(&bits.to_be_bytes());

    for block in message.chunks_exact(64) {
        let mut schedule = [0u32; 64];
        for (index, word) in block.chunks_exact(4).enumerate() {
            schedule[index] = u32::from_be_bytes(word.try_into().expect("four bytes"));
        }
        for index in 16..64 {
            let s0 = schedule[index - 15].rotate_right(7)
                ^ schedule[index - 15].rotate_right(18)
                ^ (schedule[index - 15] >> 3);
            let s1 = schedule[index - 2].rotate_right(17)
                ^ schedule[index - 2].rotate_right(19)
                ^ (schedule[index - 2] >> 10);
            schedule[index] = schedule[index - 16]
                .wrapping_add(s0)
                .wrapping_add(schedule[index - 7])
                .wrapping_add(s1);
        }
        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut h] = state;
        for index in 0..64 {
            let choose = (e & f) ^ ((!e) & g);
            let majority = (a & b) ^ (a & c) ^ (b & c);
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let temp1 = h
                .wrapping_add(choose)
                .wrapping_add(s1)
                .wrapping_add(K[index])
                .wrapping_add(schedule[index]);
            let temp2 = s0.wrapping_add(majority);
            h = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }
        for (slot, value) in state.iter_mut().zip([a, b, c, d, e, f, g, h]) {
            *slot = slot.wrapping_add(value);
        }
    }

    let mut digest = [0u8; 32];
    for (index, word) in state.iter().enumerate() {
        digest[index * 4..index * 4 + 4].copy_from_slice(&word.to_be_bytes());
    }
    digest
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn films() -> std::path::PathBuf {
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../films")
    }

    /// The whole point of the format: the file and the compiled stock describe
    /// the same film. If they ever disagree, the file is wrong or the compiler
    /// is, and either way a render done from one is not the render done from
    /// the other.
    #[test]
    fn the_files_match_the_compiled_stocks() {
        for (id, directory) in [
            ("fuji_pro400h", "fuji-pro400h"),
            ("provia_100f", "provia-100f"),
            ("ektachrome_e100", "ektachrome-e100"),
            ("velvia_50", "velvia-50"),
            ("kodak_portra_400", "portra-400"),
            ("kodak_portra_800", "portra-800"),
            ("kodak_trix400", "trix-400"),
            ("ilford_hp5plus", "hp5-plus"),
            ("kodak_ektar_100", "ektar-100"),
            ("kodak_gold200", "gold-200"),
            ("kodak_portra_160", "portra-160"),
        ] {
            let loaded = read(
                films()
                    .join(directory)
                    .join(format!("{directory}.kalofilm")),
            )
            .unwrap_or_else(|error| panic!("{id}: {error}"));
            let compiled = kallotype_core::emulsion::film_stock(id).expect("a compiled stock");
            assert_eq!(loaded.id, compiled.id);
            assert_eq!(loaded.process, compiled.process);
            assert_eq!(loaded.channels, compiled.channels);
            assert_eq!(loaded.base_density, compiled.base_density);
            assert_eq!(loaded.grains_per_um2, compiled.grains_per_um2);
            assert_eq!(loaded.layers, compiled.layers);
            assert_eq!(loaded.dyes, compiled.dyes);
            assert_eq!(loaded.mask, compiled.mask);
            assert_eq!(loaded.sigma_um, compiled.sigma_um);
            assert_eq!(loaded.cl_layer.is_some(), compiled.cl_layer.is_some());
        }
    }

    /// A byte of the tables changed is a film that is not this film, and the
    /// digest is what says so.
    #[test]
    fn an_altered_file_is_refused() {
        let directory = films().join("fuji-pro400h");
        let path = directory.join("fuji-pro400h.kalofilm");
        let mut bytes = std::fs::read(&path).expect("the committed file");
        let middle = bytes.len() / 2;
        bytes[middle] ^= 0xff;
        let scratch = std::env::temp_dir().join("kalotype-altered.kalofilm");
        std::fs::write(&scratch, &bytes).expect("write");
        match read(&scratch) {
            Err(FilmFileError::Digest { .. }) => {}
            other => panic!("expected a digest failure, got {other:?}"),
        }
        let _ = std::fs::remove_file(&scratch);
    }

    /// FIPS 180-2's published vectors: an empty message and the two standard
    /// short abcs. A hash implementation without them is a guess.
    #[test]
    fn the_digest_matches_the_published_vectors() {
        assert_eq!(
            hex(&sha256(b"")),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            hex(&sha256(b"abc")),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(
            hex(&sha256(
                b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
            )),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        );
    }
}
