//! The bench's session: one decode, many previews of it.
//!
//! A darkroom does not re-read the photograph every time the timer moves. The
//! app used to: each preview decoded the camera file, resized it, rendered and
//! wrote a PNG, and the window decoded the PNG again. The decode was the cost —
//! a 26-megapixel file takes longer to read than a bench-sized render takes to
//! draw — and it bought nothing, because every preview of one strip is the same
//! photograph.
//!
//! A session is that knowledge held for as long as the strip is on the bench.
//! It decodes once, meters once, and hands back the pixels of any development,
//! print exposure, filter pack or heat glass. It also keeps the last few frames:
//! dragging the ruler past a time and back again is a thing people do, and the
//! frame they saw a moment ago is already made.
//!
//! What a session returns is the *print* the model would write, not an
//! approximation of it: [`crate::render_image`] runs the same pipeline, and
//! [`kallotype_io::to_rgba8`] is the encoding [`kallotype_io::save`] uses.

use std::collections::{HashMap, VecDeque};
use std::path::PathBuf;
use std::sync::{Mutex, MutexGuard};

use kallotype_core::Metering;
use kallotype_io::{Image, InputEncoding, resize_to_width, to_rgba8};

use crate::error::Error;
use crate::input::read_input;
use crate::render::{Exposure, RenderOptions, render_image};
use crate::selection::{Selection, StockChoice, resolve};

/// How many frames a session remembers.
///
/// A strip is a handful of times, and the print step adds a few exposure
/// settings to the same handful. Twelve is enough for a strip and its dialled
/// print without holding a hundred megabytes of textures.
const CACHE: usize = 12;

/// What a preview session is opened on.
#[derive(Debug, Clone)]
pub struct PreviewRequest {
    /// The photograph.
    pub input: PathBuf,
    /// How to read an ordinary image.
    pub encoding: InputEncoding,
    /// Film stock id.
    pub film: String,
    /// Paper stock id.
    pub paper: String,
    /// Developer temperature in degrees Celsius.
    pub temp_c: f64,
    /// The width the bench shows the print at.
    pub width: u32,
    /// Expose through the spectral path.
    pub spectral: bool,
    /// Width of the film frame the image represents, in millimetres.
    pub frame_mm: f64,
    /// Add grain.
    pub grain: bool,
    /// Add halation.
    pub halation: bool,
    /// Add DIR couplers.
    pub couplers: bool,
    /// Render on the device when there is one.
    pub gpu: bool,
}

impl PreviewRequest {
    fn choice(&self) -> StockChoice {
        StockChoice {
            film: self.film.clone(),
            paper: self.paper.clone(),
            temp: Some(self.temp_c),
            spectral: self.spectral,
            // The app's spectral choice is the whole path, not only the
            // exposure: the print and the scan are the other two thirds of the
            // same decision.
            spectral_print: self.spectral,
            spectral_scan: self.spectral,
            ..StockChoice::default()
        }
    }
}

/// One bench frame, already encoded the way a window wants it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PreviewFrame {
    /// Pixels across.
    pub width: u32,
    /// Pixels down.
    pub height: u32,
    /// RGBA, eight bits per channel, sRGB, row-major.
    pub rgba: Vec<u8>,
}

/// The frame cache's key: everything that changes the picture.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct Key {
    minutes: u64,
    print_ev: u64,
    balance_from: Option<u64>,
    filters: String,
    heat_glass: Option<String>,
}

impl Key {
    fn new(
        minutes: f64,
        print_ev: f64,
        balance_from: Option<f64>,
        filters: &str,
        heat_glass: Option<&str>,
    ) -> Self {
        Self {
            minutes: minutes.to_bits(),
            print_ev: print_ev.to_bits(),
            balance_from: balance_from.map(f64::to_bits),
            filters: filters.to_owned(),
            heat_glass: heat_glass.map(str::to_owned),
        }
    }
}

/// The frames a session has already made, oldest first.
#[derive(Debug, Default)]
struct Cache {
    frames: HashMap<Key, PreviewFrame>,
    order: VecDeque<Key>,
}

impl Cache {
    fn get(&self, key: &Key) -> Option<PreviewFrame> {
        self.frames.get(key).cloned()
    }

    fn put(&mut self, key: Key, frame: PreviewFrame) {
        if let Some(slot) = self.frames.get_mut(&key) {
            *slot = frame;
            return;
        }
        if self.order.len() >= CACHE {
            if let Some(oldest) = self.order.pop_front() {
                self.frames.remove(&oldest);
            }
        }
        self.order.push_back(key.clone());
        self.frames.insert(key, frame);
    }
}

/// A photograph held on the bench, ready to be printed at any setting.
#[derive(Debug)]
pub struct PreviewSession {
    choice: StockChoice,
    image: Image,
    /// The frame's metered offset, solved once on the image the bench shows.
    metered_ev: f64,
    frame_mm: f64,
    grain: bool,
    halation: bool,
    couplers: bool,
    gpu: bool,
    cache: Mutex<Cache>,
}

impl PreviewSession {
    /// Read the photograph and meter it, once.
    ///
    /// The width is the bench's: the model's grain and blur belong to the
    /// sampling, so a session is opened at the size it will be looked at, just
    /// as a print is rendered at the size it will be exported.
    pub fn open(request: PreviewRequest) -> Result<Self, Error> {
        if request.width == 0 {
            return Err(Error::InvalidNumber {
                flag: "--size",
                value: 0.0,
                expected: "a positive width in pixels",
            });
        }
        // Resolve before the decode: an unknown film should be an error before
        // a camera file is read, not after.
        let choice = request.choice();
        resolve(&choice)?;

        let source = read_input(&request.input, request.encoding)?;
        let image = resize_to_width(&source, request.width);
        let metered_ev = Metering::of(&image.pixels).ev;

        Ok(Self {
            choice,
            image,
            metered_ev,
            frame_mm: request.frame_mm,
            grain: request.grain,
            halation: request.halation,
            couplers: request.couplers,
            gpu: request.gpu,
            cache: Mutex::new(Cache::default()),
        })
    }

    /// The frame this session would print at one setting.
    ///
    /// `balance_from` is the strip's one exposure: when set, the enlarger is
    /// borrowed from that development and only the negative is this frame's.
    pub fn frame(
        &self,
        minutes: f64,
        print_ev: f64,
        balance_from: Option<f64>,
        filters: &str,
        heat_glass: Option<&str>,
    ) -> Result<PreviewFrame, Error> {
        if !(minutes.is_finite() && minutes > 0.0) {
            return Err(Error::InvalidNumber {
                flag: "--dev",
                value: minutes,
                expected: "a positive number of minutes",
            });
        }
        if !print_ev.is_finite() {
            return Err(Error::InvalidNumber {
                flag: "--print-ev",
                value: print_ev,
                expected: "a finite number of stops",
            });
        }

        let key = Key::new(minutes, print_ev, balance_from, filters, heat_glass);
        if let Some(frame) = self.cache().get(&key) {
            return Ok(frame);
        }

        let mut choice = self.choice.clone();
        choice.dev_time = Some(minutes);
        choice.filters = filters.to_owned();
        choice.heat_glass = heat_glass.map(str::to_owned);
        let selection: Selection = resolve(&choice)?;

        // The source is the session's, and a render is in place. Cloning it is
        // what keeps the next frame independent; the public API hands the
        // model a decoded image and expects to lose it.
        let mut image = self.image.clone();
        let options = RenderOptions {
            ev: Exposure::Stops(self.metered_ev),
            print_ev,
            balance_from,
            frame_mm: self.frame_mm,
            grain: self.grain,
            halation: self.halation,
            couplers: self.couplers,
            gpu: self.gpu,
            ..RenderOptions::default()
        };
        render_image(&mut image, None, &selection, &options)?;

        let frame = PreviewFrame {
            width: image.width,
            height: image.height,
            rgba: to_rgba8(&image),
        };
        self.cache().put(key, frame.clone());
        Ok(frame)
    }

    /// How many frames are held, for the tests that care that the cache works.
    #[cfg(test)]
    fn held(&self) -> usize {
        self.cache().frames.len()
    }

    fn cache(&self) -> MutexGuard<'_, Cache> {
        // The cache is a scratchpad, not a lock around the model: a panic
        // while holding it cannot leave a half-rendered frame, only a frame
        // that was never inserted. Recovering the guard is the honest response.
        self.cache.lock().unwrap_or_else(|error| error.into_inner())
    }
}

#[cfg(test)]
mod tests {
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicU64, Ordering};

    use kallotype_io::{Image, save};

    use super::{PreviewRequest, PreviewSession};
    use crate::render::{Exposure, RenderOptions, render_image};
    use crate::selection::resolve;

    static NEXT: AtomicU64 = AtomicU64::new(0);

    /// A tiny photograph on disk, and the path to it.
    fn photograph() -> (PathBuf, Image) {
        let image = Image {
            width: 5,
            height: 4,
            pixels: (0..20)
                .map(|index| {
                    let value = 0.02 + f64::from(index) * 0.04;
                    [value, value * 0.8, value * 0.6]
                })
                .collect(),
        };
        let path = std::env::temp_dir().join(format!(
            "kallotype-preview-{}-{}.png",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        save(&path, &image).expect("the test photograph");
        (path, image)
    }

    fn request(path: &Path) -> PreviewRequest {
        PreviewRequest {
            input: path.to_path_buf(),
            encoding: kallotype_io::InputEncoding::Srgb,
            film: "vision3_500t".to_owned(),
            paper: "portra_endura".to_owned(),
            temp_c: 20.0,
            width: 5,
            spectral: false,
            frame_mm: 36.0,
            grain: false,
            halation: false,
            couplers: false,
            gpu: false,
        }
    }

    fn expected(
        session: &PreviewSession,
        minutes: f64,
        print_ev: f64,
        balance_from: Option<f64>,
        filters: &str,
    ) -> Image {
        let mut choice = session.choice.clone();
        choice.dev_time = Some(minutes);
        choice.filters = filters.to_owned();
        let selection = resolve(&choice).expect("the test selection");
        let mut image = session.image.clone();
        let options = RenderOptions {
            ev: Exposure::Stops(session.metered_ev),
            print_ev,
            balance_from,
            frame_mm: session.frame_mm,
            grain: session.grain,
            halation: session.halation,
            couplers: session.couplers,
            gpu: false,
            ..RenderOptions::default()
        };
        render_image(&mut image, None, &selection, &options).expect("the expected render");
        image
    }

    #[test]
    fn a_session_frame_is_the_print_at_that_time() {
        let (path, _) = photograph();
        let session = PreviewSession::open(request(&path)).expect("the session");
        let frame = session.frame(6.0, 0.0, None, "", None).expect("the frame");
        let image = expected(&session, 6.0, 0.0, None, "");
        assert_eq!(frame.width, image.width);
        assert_eq!(frame.height, image.height);
        assert_eq!(frame.rgba, kallotype_io::to_rgba8(&image));
        assert_eq!(
            frame.rgba.len(),
            (image.width * image.height * 4) as usize,
            "four channels per pixel"
        );
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn a_second_frame_at_the_same_setting_is_the_cached_one() {
        let (path, _) = photograph();
        let session = PreviewSession::open(request(&path)).expect("the session");
        let first = session.frame(6.0, 0.0, None, "", None).expect("the frame");
        let second = session
            .frame(6.0, 0.0, None, "", None)
            .expect("the cached frame");
        assert_eq!(first, second);
        assert_eq!(session.held(), 1, "one setting, one frame held");
        let other = session
            .frame(9.0, 0.0, None, "", None)
            .expect("another frame");
        assert_ne!(first, other, "nine minutes is not six");
        assert_eq!(session.held(), 2);
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn a_strip_frame_borrows_the_first_prints_balance() {
        let (path, _) = photograph();
        let session = PreviewSession::open(request(&path)).expect("the session");
        let frame = session
            .frame(12.0, 0.0, Some(6.0), "", None)
            .expect("the frame");
        let image = expected(&session, 12.0, 0.0, Some(6.0), "");
        assert_eq!(frame.rgba, kallotype_io::to_rgba8(&image));
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn filters_are_part_of_the_frame() {
        let (path, _) = photograph();
        let session = PreviewSession::open(request(&path)).expect("the session");
        let plain = session
            .frame(6.0, 0.0, None, "", None)
            .expect("the plain frame");
        let filtered = session
            .frame(6.0, 0.0, None, "30M", None)
            .expect("the filtered frame");
        assert_ne!(plain, filtered, "a colour pack changes the print");
        assert_eq!(session.held(), 2);
        let _ = std::fs::remove_file(path);
    }
}
