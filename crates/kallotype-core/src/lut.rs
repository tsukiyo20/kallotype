//! A baked lookup table for the spectral exposure.
//!
//! The hybrid reconstruction costs a non-negative least squares per pixel, which
//! is fine for a benchmark and hopeless for a 24 MP image. But the expensive part
//! produces only three numbers: the log exposure of each film layer. So the model
//! can be *distilled* into a three-dimensional table over RGB and interpolated
//! per pixel.
//!
//! The table is indexed on a **logarithmic** axis. Linear light spans several
//! decades between a shadow and a highlight, and a linear axis would spend most
//! of its resolution on values nobody photographs. Uniform steps in log10 give
//! uniform resolution in stops.

use std::path::{Path, PathBuf};

use crate::spectral::SpectralContext;

/// Magic bytes at the start of a baked table.
const MAGIC: &[u8; 4] = b"KLUT";
/// Format version. Bumped when the layout changes.
const VERSION: u16 = 1;
/// Channels per sample: the model has always produced three.
const CHANNELS: u16 = 3;
/// Largest side accepted on read, to bound allocation from a hostile file.
const MAX_SIZE: usize = 256;

/// A baked table could not be written or read.
#[derive(Debug)]
pub enum LutError {
    /// The file could not be opened, read or written.
    Io {
        /// The path that failed.
        path: PathBuf,
        /// The underlying OS error.
        source: std::io::Error,
    },
    /// The file does not start with `KLUT`.
    Magic,
    /// The file was written by a future or older layout.
    Version(u16),
    /// The declared side length is outside the accepted range.
    Size(u32),
    /// The sample count or channel count does not match the header.
    Layout,
    /// The payload does not match its checksum.
    Checksum,
}

impl std::fmt::Display for LutError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io { path, source } => write!(f, "could not access {}: {source}", path.display()),
            Self::Magic => write!(f, "not a Kallotype lookup table"),
            Self::Version(version) => write!(f, "unsupported table version {version}"),
            Self::Size(size) => write!(f, "table side {size} is outside 2..={MAX_SIZE}"),
            Self::Layout => write!(f, "the table's declared layout does not match its size"),
            Self::Checksum => write!(f, "the table is corrupt (checksum mismatch)"),
        }
    }
}

impl std::error::Error for LutError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io { source, .. } => Some(source),
            _ => None,
        }
    }
}

fn crc32(bytes: &[u8]) -> u32 {
    let mut crc = 0xFFFF_FFFF_u32;
    for byte in bytes {
        crc ^= u32::from(*byte);
        for _ in 0..8 {
            let mask = (crc & 1).wrapping_neg();
            crc = (crc >> 1) ^ (0xEDB8_8320 & mask);
        }
    }
    !crc
}

/// log10 of the smallest input the table covers.
pub const LOG_RANGE_MIN: f64 = -4.0;
/// log10 of the largest input the table covers.
pub const LOG_RANGE_MAX: f64 = 0.602_06; // log10(4.0)

/// A cubed lookup table mapping linear RGB to per-layer log exposure.
#[derive(Debug, Clone)]
pub struct ExposureLut {
    size: usize,
    /// `size^3` entries, index order `(r, g, b)`.
    data: Vec<[f32; 3]>,
}

impl ExposureLut {
    /// Bake a table by sampling `context` on a `size^3` grid.
    ///
    /// A size of 33 gives about 36 k samples: a few hundred milliseconds in
    /// release, half a megabyte on disk as `f32`.
    ///
    /// # Panics
    ///
    /// Panics if `size < 2`.
    #[must_use]
    pub fn bake(size: usize, context: &SpectralContext) -> Self {
        assert!(
            size >= 2,
            "a lookup table needs at least two samples per axis"
        );
        let mut data = Vec::with_capacity(size * size * size);
        for r in 0..size {
            let red = decode(r, size);
            for g in 0..size {
                let green = decode(g, size);
                for b in 0..size {
                    let blue = decode(b, size);
                    let log_e = context
                        .expose([red, green, blue])
                        .unwrap_or([LOG_RANGE_MIN; 3]);
                    data.push([log_e[0] as f32, log_e[1] as f32, log_e[2] as f32]);
                }
            }
        }
        Self { size, data }
    }

    /// Number of samples per axis.
    #[must_use]
    pub fn size(&self) -> usize {
        self.size
    }

    /// Bytes the table would occupy on disk as `f32`.
    #[must_use]
    pub fn byte_size(&self) -> usize {
        self.data.len() * 3 * std::mem::size_of::<f32>()
    }

    /// Write the table to `path` in the `.klut` format.
    ///
    /// Layout, little endian: magic (4), version (u16), side (u32),
    /// channels (u16), `side^3 * 3` f32, crc32 of everything before it.
    ///
    /// # Errors
    ///
    /// Returns [`LutError::Io`] if the file cannot be written.
    pub fn write(&self, path: impl AsRef<Path>) -> Result<(), LutError> {
        let path = path.as_ref();
        let mut bytes = Vec::with_capacity(12 + self.data.len() * 12 + 4);
        bytes.extend_from_slice(MAGIC);
        bytes.extend_from_slice(&VERSION.to_le_bytes());
        bytes.extend_from_slice(&(self.size as u32).to_le_bytes());
        bytes.extend_from_slice(&CHANNELS.to_le_bytes());
        for entry in &self.data {
            for value in entry {
                bytes.extend_from_slice(&value.to_le_bytes());
            }
        }
        let checksum = crc32(&bytes);
        bytes.extend_from_slice(&checksum.to_le_bytes());

        std::fs::write(path, bytes).map_err(|source| LutError::Io {
            path: path.to_path_buf(),
            source,
        })
    }

    /// Read a table written by [`Self::write`].
    ///
    /// # Errors
    ///
    /// Returns a [`LutError`] for a missing file, a foreign format, a future
    /// version, a size outside `2..=256`, a layout mismatch, or a bad checksum.
    pub fn read(path: impl AsRef<Path>) -> Result<Self, LutError> {
        let path = path.as_ref();
        let bytes = std::fs::read(path).map_err(|source| LutError::Io {
            path: path.to_path_buf(),
            source,
        })?;

        if bytes.len() < 16 || &bytes[0..4] != MAGIC {
            return Err(LutError::Magic);
        }
        let version = u16::from_le_bytes([bytes[4], bytes[5]]);
        if version != VERSION {
            return Err(LutError::Version(version));
        }
        let size = u32::from_le_bytes([bytes[6], bytes[7], bytes[8], bytes[9]]) as usize;
        if !(2..=MAX_SIZE).contains(&size) {
            return Err(LutError::Size(size as u32));
        }
        let channels = u16::from_le_bytes([bytes[10], bytes[11]]);
        if channels != CHANNELS {
            return Err(LutError::Layout);
        }

        let expected = 12 + size * size * size * usize::from(CHANNELS) * 4;
        if bytes.len() != expected + 4 {
            return Err(LutError::Layout);
        }
        let stored = u32::from_le_bytes([
            bytes[expected],
            bytes[expected + 1],
            bytes[expected + 2],
            bytes[expected + 3],
        ]);
        if crc32(&bytes[..expected]) != stored {
            return Err(LutError::Checksum);
        }

        let mut data = Vec::with_capacity(size * size * size);
        for chunk in bytes[12..expected].chunks_exact(12) {
            let mut entry = [0.0_f32; 3];
            for (index, value) in entry.iter_mut().enumerate() {
                let offset = index * 4;
                *value = f32::from_le_bytes([
                    chunk[offset],
                    chunk[offset + 1],
                    chunk[offset + 2],
                    chunk[offset + 3],
                ]);
            }
            data.push(entry);
        }

        Ok(Self { size, data })
    }

    /// Trilinear interpolation, clamped at the edges.
    #[must_use]
    pub fn sample(&self, rgb: [f64; 3]) -> [f64; 3] {
        let positions = rgb.map(|value| encode(value) * (self.size - 1) as f64);
        let lower = positions.map(|p| (p.floor() as usize).min(self.size - 1));
        let upper = lower.map(|l| (l + 1).min(self.size - 1));
        let weights = std::array::from_fn::<f64, 3, _>(|axis| {
            let p = positions[axis];
            let base = lower[axis] as f64;
            (p - base).clamp(0.0, 1.0)
        });

        let mut out = [0.0_f64; 3];
        for corner in 0..8 {
            let pick = |axis: usize| {
                if (corner >> axis) & 1 == 1 {
                    upper[axis]
                } else {
                    lower[axis]
                }
            };
            let weight = (0..3).fold(1.0, |acc, axis| {
                acc * if (corner >> axis) & 1 == 1 {
                    weights[axis]
                } else {
                    1.0 - weights[axis]
                }
            });
            let index = (pick(0) * self.size + pick(1)) * self.size + pick(2);
            let entry = self.data[index];
            for channel in 0..3 {
                out[channel] += weight * f64::from(entry[channel]);
            }
        }
        out
    }
}

/// Map a linear value to the `[0, 1]` table coordinate.
fn encode(value: f64) -> f64 {
    let log = value.max(1e-10).log10();
    ((log - LOG_RANGE_MIN) / (LOG_RANGE_MAX - LOG_RANGE_MIN)).clamp(0.0, 1.0)
}

/// Inverse of [`encode`].
fn decode(index: usize, size: usize) -> f64 {
    let u = index as f64 / (size - 1) as f64;
    10.0_f64.powf(LOG_RANGE_MIN + u * (LOG_RANGE_MAX - LOG_RANGE_MIN))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encode_decode_round_trip() {
        for value in [0.0005, 0.01, 0.18, 1.0, 3.0] {
            let round_trip =
                10.0_f64.powf(LOG_RANGE_MIN + encode(value) * (LOG_RANGE_MAX - LOG_RANGE_MIN));
            assert!(
                (round_trip - value).abs() < 1e-3 * value.max(1.0),
                "{value} -> {round_trip}"
            );
        }
    }

    #[test]
    fn the_table_matches_the_model_it_was_baked_from() {
        let context = SpectralContext::new();
        let lut = ExposureLut::bake(33, &context);

        // The error is strongly skewed: the mean is tiny and the tail lives in
        // the extreme corners, where the polynomial reconstruction clamps at
        // zero and the mapping has a kink. Asserting a single maximum would
        // either fail on a corner or hide the distribution.
        let mut errors = Vec::new();
        for r in 0..10 {
            for g in 0..10 {
                for b in 0..10 {
                    let rgb = [
                        0.01 + 0.09 * f64::from(r),
                        0.01 + 0.09 * f64::from(g),
                        0.01 + 0.09 * f64::from(b),
                    ];
                    let direct = context.expose(rgb).unwrap();
                    let baked = lut.sample(rgb);
                    for channel in 0..3 {
                        errors.push((direct[channel] - baked[channel]).abs());
                    }
                }
            }
        }
        errors.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let count = errors.len();
        let mean = errors.iter().sum::<f64>() / count as f64;
        let p99 = errors[count * 99 / 100];

        assert!(mean < 0.005, "mean error {mean} decades");
        assert!(p99 < 0.05, "p99 error {p99} decades");
    }

    #[test]
    fn a_written_table_reads_back_identical() {
        let context = SpectralContext::new();
        let table = ExposureLut::bake(9, &context);

        let path = std::env::temp_dir().join(format!("klut-test-{}.klut", std::process::id()));
        table.write(&path).expect("write");
        let loaded = ExposureLut::read(&path).expect("read");
        let _ = std::fs::remove_file(&path);

        assert_eq!(loaded.size(), table.size());
        let probe = [0.2, 0.35, 0.05];
        assert_eq!(loaded.sample(probe), table.sample(probe));
    }

    #[test]
    fn a_corrupt_table_is_rejected() {
        let context = SpectralContext::new();
        let table = ExposureLut::bake(4, &context);
        let path = std::env::temp_dir().join(format!("klut-bad-{}.klut", std::process::id()));
        table.write(&path).expect("write");

        let mut bytes = std::fs::read(&path).expect("read back");
        let last = bytes.len() - 1;
        bytes[last] ^= 0xFF;
        std::fs::write(&path, &bytes).expect("rewrite");

        let result = ExposureLut::read(&path);
        let _ = std::fs::remove_file(&path);
        assert!(matches!(result, Err(LutError::Checksum)), "{result:?}");
    }

    #[test]
    fn the_table_is_bounded_by_its_inputs() {
        let context = SpectralContext::new();
        let lut = ExposureLut::bake(9, &context);
        for rgb in [[0.0; 3], [1.0; 3], [10.0; 3]] {
            let out = lut.sample(rgb);
            for value in out {
                assert!(value.is_finite());
            }
        }
    }
}
