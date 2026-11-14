//! Reading the photograph: an ordinary image, or a camera raw.

use std::path::Path;

use kallotype_io::{Image, InputEncoding, load};

use crate::error::Error;

/// Read the input, from a camera raw when it is one and the build has a
/// decoder.
///
/// A raw file is scene-referred linear by construction, so `--input-encoding`
/// does not apply to it: the value is taken as the file's own, and a user who
/// asked for `srgb` on a `.nef` is not obeyed, because obeying would apply a
/// transfer curve to data that never had one. Every command that reads a
/// photograph reads it through here for that reason.
pub fn read_input(path: &Path, encoding: InputEncoding) -> Result<Image, Error> {
    #[cfg(feature = "raw")]
    if kallotype_raw::handles(path) {
        return kallotype_raw::load(path).map_err(|source| Error::Raw {
            path: path.to_path_buf(),
            message: source.to_string(),
        });
    }
    #[cfg(not(feature = "raw"))]
    if looks_like_raw(path) {
        return Err(Error::Raw {
            path: path.to_path_buf(),
            message: "this build has no raw decoder; rebuild with `--features raw`, or \
                      convert the file and pass --input-encoding linear"
                .to_string(),
        });
    }
    load(path, encoding).map_err(|source| Error::Read {
        path: path.to_path_buf(),
        source,
    })
}

/// A short list of raw extensions, and only for the error message: without the
/// `raw` feature there is no decoder to ask, and "unsupported image format" is
/// a poor answer to someone who passed a camera file.
#[cfg(not(feature = "raw"))]
const RAW_EXTENSIONS: &[&str] = &[
    "3fr", "arw", "cr2", "cr3", "dng", "iiq", "nef", "nrw", "orf", "pef", "raf", "rw2", "srw",
];

#[cfg(not(feature = "raw"))]
fn looks_like_raw(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| RAW_EXTENSIONS.contains(&extension.to_ascii_lowercase().as_str()))
}
