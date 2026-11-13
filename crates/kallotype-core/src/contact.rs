//! The contact proof: the film laid on paper, exposed once.
//!
//! A print is made frame by frame, and each frame gets its own exposure — that
//! is what the enlarger's test strip is for. A **contact proof** is the other
//! arrangement: the negative lies flat on the paper, the whole sheet is exposed
//! once, and no frame is corrected. What the paper then says is not what the
//! frames could look like, but what the film actually carries, relative to the
//! rest of the roll.
//!
//! That difference is the whole value of a proof, and it is also why this module
//! cannot be built out of `render`: a render solves one exposure per picture,
//! and a proof must not solve any.
//!
//! Two consequences are modelled here rather than drawn:
//!
//! * The **rebate** is clear film, so it prints black; the sprocket holes are
//!   holes, so they print black as well. A negative's contact proof therefore
//!   has a black band along each frame, and the edge markings are the light
//!   marks on it. (The classic "black border with white sprocket holes" is a
//!   *positive* film: on a slide the unexposed rebate becomes black dye and the
//!   holes are the only thing light gets through.)
//! * **One exposure.** The sheet is printed on the middle frame's balance: a
//!   laboratory's average printer, not a per-frame correction. The frames that
//!   were developed longer than that print denser, and the ones developed less
//!   print thinner, which is the comparison the sheet exists for.
//!
//! The layout is one strip per development, not one strip carrying every
//! development: five development times are five pieces of film, and a sheet
//! that showed them as one continuous strip would be claiming an order the
//! film never had.

use crate::development::DevelopmentParams;
use crate::emulsion::{FilmProcess, FilmStock, PaperStock};
use crate::pipeline::{Finishing, RenderParams};

/// The image area of one 35 mm frame, across the film.
pub const FRAME_W_MM: f64 = 36.0;
/// The image area of one 35 mm frame, along the film.
pub const FRAME_H_MM: f64 = 24.0;
/// The clear film on each side of a 35 mm frame: 35 mm of film, 24 mm of image.
pub const REBATE_MM: f64 = 5.5;
/// The film left beyond the frame where the strip was cut.
pub const CUT_MM: f64 = 2.0;
/// Paper between two strips on the sheet.
pub const GAP_MM: f64 = 6.0;
/// Paper around the strips.
pub const MARGIN_MM: f64 = 12.0;
/// How the sheet's strips are put in rows.
pub const COLUMNS: usize = 3;

/// The development ladder a proof is made for when nobody names one: the same
/// three-to-fifteen minutes the interface's roll carries.
pub const LADDER_MINUTES: [f64; 5] = [3.0, 6.0, 9.0, 12.0, 15.0];

/// One frame on the sheet, in pixels.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct FrameRect {
    /// Which frame on the roll, counting from one.
    pub number: usize,
    /// How long this frame was developed, in minutes. Filled in by
    /// [`print()`].
    pub minutes: f64,
    /// Left edge of the image area.
    pub x: usize,
    /// Top edge of the image area.
    pub y: usize,
    /// Width of the image area.
    pub width: usize,
    /// Height of the image area.
    pub height: usize,
}

/// Which way the strips lie on the paper.
///
/// A 35 mm frame is 24 mm across the film and 36 mm along it, so a strip is a
/// long rectangle with its perforations on the long edges — and a photograph
/// made with the camera on its side lies sideways on it. The sheet is paper,
/// and strips can be laid either way: a proof of a vertical frame lays them
/// down so the pictures stand up, which is how a photographer lays out a proof
/// sheet, because the point of one is to look at the pictures.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Strips {
    /// The film's own way: the frame is 36 mm along the strip.
    Horizontal,
    /// The strip turned a quarter turn: the frame is 36 mm down the strip and
    /// the edge markings run down the sheet.
    Vertical,
}

/// The sheet's physical arrangement, resolved to pixels.
///
/// Kept separate from the render so that a caller can size the frame before
/// asking for it — the photo has to be cropped and sampled at exactly this
/// width, because a sheet scaled afterwards would be a lie about grain and
/// about the size of the film.
#[derive(Debug, Clone, PartialEq)]
pub struct SheetGeometry {
    /// Output resolution, in dots per inch.
    pub dpi: f64,
    /// Sheet width in pixels.
    pub width: usize,
    /// Sheet height in pixels.
    pub height: usize,
    /// Paper margin around the strips, in pixels.
    pub margin: usize,
    /// The frame's pixel size, which is the size a frame is developed at.
    pub frame: (usize, usize),
    /// Which way the strips lie.
    pub strips: Strips,
    /// One rect per development, in the order they were given.
    pub frames: Vec<FrameRect>,
}

impl SheetGeometry {
    /// Lay `count` single-frame strips on a sheet at `dpi`.
    ///
    /// # Panics
    ///
    /// Cannot panic: `count` is clamped to at least one, and the dpi is clamped
    /// to a sane positive range.
    #[must_use]
    pub fn new(count: usize, dpi: f64, strips: Strips) -> Self {
        let count = count.max(1);
        let dpi = if dpi.is_finite() && dpi > 0.0 {
            dpi.clamp(72.0, 2400.0)
        } else {
            600.0
        };
        let per_mm = dpi / 25.4;
        let px = |mm: f64| (mm * per_mm).round() as usize;

        // The frame as the film carries it: 36 mm along the strip and 24 mm
        // across it, whichever way the strip is laid on the paper.
        let (long, short) = (px(FRAME_W_MM), px(FRAME_H_MM));
        let frame = match strips {
            Strips::Horizontal => (long, short),
            Strips::Vertical => (short, long),
        };
        let cut = px(CUT_MM);
        let rebate = px(REBATE_MM);
        let gap = px(GAP_MM);
        let margin = px(MARGIN_MM);
        // The strip: the frame, the cut ends at the ends of the strip, and the
        // clear film along its sides.
        let strip = match strips {
            Strips::Horizontal => (frame.0 + cut * 2, frame.1 + rebate * 2),
            Strips::Vertical => (frame.0 + rebate * 2, frame.1 + cut * 2),
        };
        let (across, along) = match strips {
            Strips::Horizontal => (cut, rebate),
            Strips::Vertical => (rebate, cut),
        };

        let columns = COLUMNS.min(count);
        let rows = count.div_ceil(columns);
        let width = margin * 2 + columns * strip.0 + gap * columns.saturating_sub(1);
        let height = margin * 2 + rows * strip.1 + gap * rows.saturating_sub(1);

        let mut frames = Vec::with_capacity(count);
        for index in 0..count {
            let column = index % columns;
            let row = index / columns;
            frames.push(FrameRect {
                number: index + 1,
                minutes: 0.0,
                x: margin + column * (strip.0 + gap) + across,
                y: margin + row * (strip.1 + gap) + along,
                width: frame.0,
                height: frame.1,
            });
        }

        Self {
            dpi,
            width,
            height,
            margin,
            frame,
            strips,
            frames,
        }
    }

    /// The strip a frame sits in: the image plus its rebate and cut edges.
    #[must_use]
    pub fn strip_of(&self, frame: &FrameRect) -> (usize, usize, usize, usize) {
        let per_mm = self.dpi / 25.4;
        let cut = (CUT_MM * per_mm).round() as usize;
        let rebate = (REBATE_MM * per_mm).round() as usize;
        // Across the strip is the cut end when the strip lies along it, and the
        // rebate when it does not.
        let (across, along) = match self.strips {
            Strips::Horizontal => (cut, rebate),
            Strips::Vertical => (rebate, cut),
        };
        (
            frame.x - across,
            frame.y - along,
            frame.width + across * 2,
            frame.height + along * 2,
        )
    }
}

/// Everything the proof is printed with.
pub struct ContactSpec {
    /// The negative.
    pub film: &'static FilmStock,
    /// The paper it lies on.
    pub paper: &'static PaperStock,
    /// One development per strip, in the order the strips are laid.
    pub developments: Vec<DevelopmentParams>,
    /// The exposure the frame was given, in stops.
    pub exposure_ev: f64,
    /// Enlarger exposure on top of the solved balance, in stops.
    pub print_ev: f64,
    /// Expose and print through the spectral model.
    pub spectral: bool,
    /// The film's own blur.
    pub emulsion: bool,
    /// Grain.
    pub grain: bool,
    /// Halation.
    pub halation: bool,
    /// DIR couplers.
    pub couplers: bool,
    /// Print the edge markings: the stock, the frame number, the development.
    pub edge_codes: bool,
}

/// A printed contact proof.
#[derive(Debug, Clone)]
pub struct Contact {
    /// Where everything is.
    pub geometry: SheetGeometry,
    /// The print, row-major, linear light.
    pub pixels: Vec<[f64; 3]>,
}

/// Develop one frame at every time, lay the strips on paper, and expose it once.
///
/// `frame` is the photograph already sampled at `geometry.frame` — the caller
/// crops and resizes, because that is I/O and this crate has none. It is the
/// picture the way up the photographer made it; when the strips lie vertically
/// the picture is the same picture, and the film under it is laid down turned.
///
/// # Panics
///
/// Panics when `frame` does not hold exactly `geometry.frame.0 * geometry.frame.1`
/// pixels, which is a caller's bug; a silent short frame would print as a hole
/// in the sheet. It also panics if the geometry and the development list differ
/// in length.
#[must_use]
pub fn print(frame: &[[f64; 3]], geometry: &SheetGeometry, spec: &ContactSpec) -> Contact {
    let (frame_w, frame_h) = geometry.frame;
    assert_eq!(
        frame.len(),
        frame_w * frame_h,
        "the frame must be sampled at the sheet's frame size"
    );
    assert_eq!(
        geometry.frames.len(),
        spec.developments.len(),
        "one strip per development, and one development per strip"
    );
    let per_mm = geometry.dpi / 25.4;
    let px = |mm: f64| (mm * per_mm).round() as usize;

    // The strip is always drawn the film's own way — 36 mm along it — and then
    // laid on the paper. A vertical strip is that drawing turned, not a second
    // drawing, so the picture reaches it a quarter turn the other way.
    let (laid_w, laid_h) = (px(FRAME_W_MM), px(FRAME_H_MM));
    let stood = (geometry.strips == Strips::Vertical)
        .then(|| turned_pixels(frame, frame_w, frame_h, Turn::Clockwise));
    let frame = stood.as_deref().unwrap_or(frame);

    // One finishing chain, shared by every strip: the five strips are five
    // developments of one exposure, so they carry the same grain and the same
    // optics. A different seed per strip would say the strips were cut from
    // different negatives, and they were not.
    let pixel_um = FRAME_W_MM * 1000.0 / laid_w as f64;
    let emulsion = spec
        .emulsion
        .then(|| crate::mtf::EmulsionBlur::for_stock(spec.film, pixel_um));
    let halation = spec
        .halation
        .then(|| crate::halation::Halation::typical(pixel_um));
    let couplers = spec
        .couplers
        .then(|| crate::couplers::Couplers::typical(pixel_um));
    let grain = spec
        .grain
        .then(|| crate::grain::GrainField::for_stock(laid_w, laid_h, FRAME_W_MM, 0, spec.film));
    let finishing = Finishing {
        emulsion: emulsion.as_ref(),
        halation: halation.as_ref(),
        grain: grain.as_ref(),
        couplers: couplers.as_ref(),
        interimage: None,
    };
    let bare = Finishing {
        emulsion: None,
        halation: None,
        grain: None,
        couplers: None,
        interimage: None,
    };

    // Develop every strip. `PreparedRender` freezes one development's curves,
    // so the ladder is a vector of them rather than one reused render.
    let mut prepared = Vec::with_capacity(spec.developments.len());
    let mut negatives = Vec::with_capacity(spec.developments.len());
    for development in &spec.developments {
        let params = RenderParams {
            film: spec.film,
            paper: spec.paper,
            development: *development,
            exposure_ev: spec.exposure_ev,
            spectral: spec.spectral,
            camera: crate::spectral::CameraProfile::default(),
            lut_size: 0,
            spectral_print: spec.spectral,
            spectral_scan: false,
            interimage: false,
            print_exposure_ev: spec.print_ev,
            filters: crate::filters::FilterPack::none(),
            heat_glass: None,
        };
        let render = params.prepare();
        negatives.push(render.develop(frame, laid_w, laid_h, &finishing));
        prepared.push(render);
    }

    // The sheet's one exposure: the middle development's balance. A roll has an
    // average, and the average is what a laboratory printer prints it at.
    let printer = &prepared[prepared.len() / 2];
    let paper_white = printer.positive([12.0; 3]);
    let mut pixels = vec![paper_white; geometry.width * geometry.height];

    // One strip on its own paper, drawn the film's way: the frame is 36 mm
    // along it and the markings sit in the clear film above and below.
    let cut = px(CUT_MM);
    let clear = px(REBATE_MM);
    let strip_size = (laid_w + cut * 2, laid_h + clear * 2);
    let mut strip_rect = FrameRect {
        number: 0,
        minutes: 0.0,
        x: cut,
        y: clear,
        width: laid_w,
        height: laid_h,
    };
    let strip_geometry = SheetGeometry {
        dpi: geometry.dpi,
        width: strip_size.0,
        height: strip_size.1,
        margin: 0,
        frame: (laid_w, laid_h),
        strips: Strips::Horizontal,
        frames: vec![strip_rect],
    };

    let mut geometry = geometry.clone();
    for index in 0..geometry.frames.len() {
        let mut rect = geometry.frames[index];
        rect.minutes = spec.developments[index].time_min;
        geometry.frames[index] = rect;
        // The strip is drawn on its own canvas, so the edge code is stamped
        // with this canvas's rect — but the code has to name the development
        // this strip came from, not the canvas's placeholder.
        strip_rect.number = rect.number;
        strip_rect.minutes = rect.minutes;

        // The unexposed rebate: base, fog and mask, developed for this strip's
        // time. Fog grows with development, so each strip has its own.
        let rebate = prepared[index].develop(&[[0.0; 3]], 1, 1, &bare).densities[0];
        let mut strip = vec![printer.positive(rebate); strip_size.0 * strip_size.1];
        // Perforations are holes in the film, so they print as light: they
        // are drawn before the markings, which sit between them and the frame.
        punch_holes(&mut strip, &strip_geometry, &strip_rect, printer, per_mm);
        if spec.edge_codes {
            stamp_strip(
                &mut strip,
                &strip_geometry,
                &strip_rect,
                spec,
                printer,
                rebate,
            );
        }
        // The frame itself: the strip's printed image, laid over its rebate.
        blit(
            &mut strip,
            strip_size.0,
            &printer.print(&negatives[index]),
            laid_w,
            laid_h,
            cut,
            clear,
        );

        let (sx, sy, _, _) = geometry.strip_of(&rect);
        match geometry.strips {
            Strips::Horizontal => blit(
                &mut pixels,
                geometry.width,
                &strip,
                strip_size.0,
                strip_size.1,
                sx,
                sy,
            ),
            Strips::Vertical => {
                // The paper's strips lie down the sheet; the strip itself is
                // the same print, turned.
                let stood = turned_pixels(&strip, strip_size.0, strip_size.1, Turn::Anticlockwise);
                blit(
                    &mut pixels,
                    geometry.width,
                    &stood,
                    strip_size.1,
                    strip_size.0,
                    sx,
                    sy,
                );
            }
        }
    }

    Contact { geometry, pixels }
}

/// Which way a quarter turn goes.
#[derive(Debug, Clone, Copy)]
enum Turn {
    /// The picture's top edge goes to its left edge.
    Anticlockwise,
    /// The picture's top edge goes to its right edge.
    Clockwise,
}

/// Turn a picture a quarter turn, without resampling a pixel.
fn turned_pixels(pixels: &[[f64; 3]], width: usize, height: usize, turn: Turn) -> Vec<[f64; 3]> {
    let mut out = vec![[0.0; 3]; pixels.len()];
    // The turned picture is `height` wide and `width` tall.
    for y in 0..width {
        for x in 0..height {
            out[y * height + x] = match turn {
                Turn::Anticlockwise => pixels[x * width + (width - 1 - y)],
                Turn::Clockwise => pixels[(height - 1 - x) * width + y],
            };
        }
    }
    out
}

/// Copy a block into the canvas at `(x, y)`.
fn blit(
    canvas: &mut [[f64; 3]],
    canvas_width: usize,
    block: &[[f64; 3]],
    block_width: usize,
    block_height: usize,
    x: usize,
    y: usize,
) {
    for row in 0..block_height {
        let from = row * block_width;
        let to = (y + row) * canvas_width + x;
        canvas[to..to + block_width].copy_from_slice(&block[from..from + block_width]);
    }
}

/// Sprocket holes: 1.98 mm along the film, 2.79 mm across it, on a 4.75 mm pitch.
fn punch_holes(
    canvas: &mut [[f64; 3]],
    geometry: &SheetGeometry,
    rect: &FrameRect,
    printer: &crate::pipeline::PreparedRender,
    per_mm: f64,
) {
    let hole = printer.positive([0.0; 3]);
    let (sx, sy, sw, _) = geometry.strip_of(rect);
    let width = (1.98 * per_mm).round() as usize;
    let height = (2.79 * per_mm).round() as usize;
    let pitch = (4.75 * per_mm).round() as usize;
    let rebate = (REBATE_MM * per_mm).round() as usize;
    let cut = (CUT_MM * per_mm).round() as usize;
    let radius = (0.4 * per_mm).round().max(1.0) as usize;
    let top = sy + (rebate - height) / 2;
    let bottom = rect.y + rect.height + (rebate - height) / 2;
    let mut x = sx + cut;
    while x + width <= sx + sw {
        rounded(
            canvas,
            geometry.width,
            (x, top, width, height),
            radius,
            hole,
        );
        rounded(
            canvas,
            geometry.width,
            (x, bottom, width, height),
            radius,
            hole,
        );
        x += pitch;
    }
}

/// A rectangle with rounded corners, filled row by row.
fn rounded(
    canvas: &mut [[f64; 3]],
    width: usize,
    rect: (usize, usize, usize, usize),
    radius: usize,
    colour: [f64; 3],
) {
    let (x, y, w, h) = rect;
    for row in 0..h {
        let inset = if row < radius {
            let dy = radius - row;
            radius - ((radius * radius - dy * dy) as f64).sqrt() as usize
        } else if row >= h.saturating_sub(radius) {
            let dy = radius - (h - 1 - row);
            radius - ((radius * radius - dy * dy) as f64).sqrt() as usize
        } else {
            0
        };
        if inset * 2 >= w {
            continue;
        }
        let start = (y + row) * width + x + inset;
        canvas[start..start + w - inset * 2].fill(colour);
    }
}

/// The edge markings of one strip: the stock on the top rebate, the frame and
/// the development on the bottom one.
fn stamp_strip(
    canvas: &mut [[f64; 3]],
    geometry: &SheetGeometry,
    rect: &FrameRect,
    spec: &ContactSpec,
    printer: &crate::pipeline::PreparedRender,
    rebate: [f64; 3],
) {
    let per_mm = geometry.dpi / 25.4;
    // 1.2 mm of text, in the 1.35 mm between the perforations and the frame:
    // that is where a real edge code sits, and for the same reason.
    let scale = ((1.2 * per_mm) / 7.0).round().max(1.0) as usize;
    let gap = (0.06 * per_mm).round() as usize;
    let text = printer.positive(std::array::from_fn(|channel| rebate[channel] + 1.2));
    let (sx, _, sw, _) = geometry.strip_of(rect);
    let height = 7 * scale;
    let top = rect.y - height - gap;
    let bottom = rect.y + rect.height + gap;

    let mut line = String::from("KALLOTYPE ");
    line.push_str(spec.film.short);
    let fitted = fit(&line, sw.saturating_sub(scale * 2), scale);
    stamp(
        canvas,
        geometry.width,
        sx + scale,
        top,
        scale,
        &fitted,
        text,
    );

    let lower = format!("{:02}  {:.1} MIN", rect.number, rect.minutes);
    stamp(
        canvas,
        geometry.width,
        sx + scale,
        bottom,
        scale,
        &lower,
        text,
    );
}

/// Keep the start of `text` that fits in `width` pixels.
fn fit(text: &str, width: usize, scale: usize) -> String {
    let advance = 6 * scale;
    let room = width / advance.max(1);
    text.chars().take(room).collect()
}

/// Draw one line of 5×7 text, cell `scale` pixels square.
fn stamp(
    canvas: &mut [[f64; 3]],
    canvas_width: usize,
    x: usize,
    y: usize,
    scale: usize,
    text: &str,
    colour: [f64; 3],
) {
    let advance = 6 * scale;
    for (index, character) in text.chars().enumerate() {
        let Some(rows) = glyph(character) else {
            continue;
        };
        let origin = x + index * advance;
        for (row, bits) in rows.iter().enumerate() {
            for (column, bit) in bits.chars().enumerate() {
                if bit != '1' {
                    continue;
                }
                for dy in 0..scale {
                    let line = (y + row * scale + dy) * canvas_width + origin + column * scale;
                    canvas[line..line + scale].fill(colour);
                }
            }
        }
    }
}

/// A 5×7 bitmap font: what a strip's edge is legible enough for.
///
/// It is a drawing, not a typeface: the model has no fonts and does not want
/// one. The glyphs are the ones a frame number and a stock name need.
fn glyph(character: char) -> Option<[&'static str; 7]> {
    let glyphs: &[(char, [&str; 7])] = &[
        (
            'A',
            [
                "01110", "10001", "10001", "11111", "10001", "10001", "10001",
            ],
        ),
        (
            'B',
            [
                "11110", "10001", "10001", "11110", "10001", "10001", "11110",
            ],
        ),
        (
            'C',
            [
                "01110", "10001", "10000", "10000", "10000", "10001", "01110",
            ],
        ),
        (
            'D',
            [
                "11110", "10001", "10001", "10001", "10001", "10001", "11110",
            ],
        ),
        (
            'E',
            [
                "11111", "10000", "10000", "11110", "10000", "10000", "11111",
            ],
        ),
        (
            'F',
            [
                "11111", "10000", "10000", "11110", "10000", "10000", "10000",
            ],
        ),
        (
            'G',
            [
                "01110", "10001", "10000", "10111", "10001", "10001", "01110",
            ],
        ),
        (
            'H',
            [
                "10001", "10001", "10001", "11111", "10001", "10001", "10001",
            ],
        ),
        (
            'I',
            [
                "11111", "00100", "00100", "00100", "00100", "00100", "11111",
            ],
        ),
        (
            'J',
            [
                "00111", "00010", "00010", "00010", "00010", "10010", "01100",
            ],
        ),
        (
            'K',
            [
                "10001", "10010", "10100", "11000", "10100", "10010", "10001",
            ],
        ),
        (
            'L',
            [
                "10000", "10000", "10000", "10000", "10000", "10000", "11111",
            ],
        ),
        (
            'M',
            [
                "10001", "11011", "10101", "10101", "10001", "10001", "10001",
            ],
        ),
        (
            'N',
            [
                "10001", "11001", "10101", "10011", "10001", "10001", "10001",
            ],
        ),
        (
            'O',
            [
                "01110", "10001", "10001", "10001", "10001", "10001", "01110",
            ],
        ),
        (
            'P',
            [
                "11110", "10001", "10001", "11110", "10000", "10000", "10000",
            ],
        ),
        (
            'Q',
            [
                "01110", "10001", "10001", "10001", "10101", "10010", "01101",
            ],
        ),
        (
            'R',
            [
                "11110", "10001", "10001", "11110", "10100", "10010", "10001",
            ],
        ),
        (
            'S',
            [
                "01111", "10000", "10000", "01110", "00001", "00001", "11110",
            ],
        ),
        (
            'T',
            [
                "11111", "00100", "00100", "00100", "00100", "00100", "00100",
            ],
        ),
        (
            'U',
            [
                "10001", "10001", "10001", "10001", "10001", "10001", "01110",
            ],
        ),
        (
            'V',
            [
                "10001", "10001", "10001", "10001", "10001", "01010", "00100",
            ],
        ),
        (
            'W',
            [
                "10001", "10001", "10001", "10101", "10101", "10101", "01010",
            ],
        ),
        (
            'X',
            [
                "10001", "10001", "01010", "00100", "01010", "10001", "10001",
            ],
        ),
        (
            'Y',
            [
                "10001", "10001", "01010", "00100", "00100", "00100", "00100",
            ],
        ),
        (
            'Z',
            [
                "11111", "00001", "00010", "00100", "01000", "10000", "11111",
            ],
        ),
        (
            '0',
            [
                "01110", "10001", "10011", "10101", "11001", "10001", "01110",
            ],
        ),
        (
            '1',
            [
                "00100", "01100", "00100", "00100", "00100", "00100", "01110",
            ],
        ),
        (
            '2',
            [
                "01110", "10001", "00001", "00010", "00100", "01000", "11111",
            ],
        ),
        (
            '3',
            [
                "11111", "00010", "00100", "00010", "00001", "10001", "01110",
            ],
        ),
        (
            '4',
            [
                "00010", "00110", "01010", "10010", "11111", "00010", "00010",
            ],
        ),
        (
            '5',
            [
                "11111", "10000", "11110", "00001", "00001", "10001", "01110",
            ],
        ),
        (
            '6',
            [
                "00110", "01000", "10000", "11110", "10001", "10001", "01110",
            ],
        ),
        (
            '7',
            [
                "11111", "00001", "00010", "00100", "01000", "01000", "01000",
            ],
        ),
        (
            '8',
            [
                "01110", "10001", "10001", "01110", "10001", "10001", "01110",
            ],
        ),
        (
            '9',
            [
                "01110", "10001", "10001", "01111", "00001", "00010", "01100",
            ],
        ),
        (
            '-',
            [
                "00000", "00000", "00000", "11111", "00000", "00000", "00000",
            ],
        ),
        (
            '.',
            [
                "00000", "00000", "00000", "00000", "00000", "01100", "01100",
            ],
        ),
        (
            ' ',
            [
                "00000", "00000", "00000", "00000", "00000", "00000", "00000",
            ],
        ),
    ];
    glyphs
        .iter()
        .find(|(candidate, _)| *candidate == character)
        .map(|(_, rows)| *rows)
}

/// Whether a stock can be contact printed at all.
///
/// A reversal is its own picture: there is no paper between the film and the
/// eye, so there is nothing for a contact proof to be. The caller turns this
/// into the error a person reads; the model just says what it knows.
#[must_use]
pub fn printable(film: &FilmStock) -> bool {
    film.process != FilmProcess::Reversal
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::emulsion::{film_stock, paper_stock};

    fn frame(width: usize, height: usize) -> Vec<[f64; 3]> {
        let mut pixels = Vec::with_capacity(width * height);
        for row in 0..height {
            for column in 0..width {
                // A horizontal ramp with a bright square, so the print has
                // something with structure in it.
                let ramp = column as f64 / width as f64;
                let square = (row > height / 3 && row < height / 2)
                    && (column > width / 3 && column < width / 2);
                let value = if square { 0.85 } else { 0.02 + 0.6 * ramp };
                pixels.push([value, value * 0.9, value * 0.8]);
            }
        }
        pixels
    }

    fn spec(times: &[f64]) -> (ContactSpec, SheetGeometry, Vec<[f64; 3]>) {
        let film = film_stock("kodak_portra_400").expect("film");
        let paper = paper_stock("portra_endura").expect("paper");
        let geometry = SheetGeometry::new(times.len(), 300.0, Strips::Horizontal);
        let pixels = frame(geometry.frame.0, geometry.frame.1);
        let developments = times
            .iter()
            .map(|minutes| DevelopmentParams {
                time_min: *minutes,
                temp_c: 20.0,
                reference_time_min: film.reference_time_min,
                reference_temp_c: film.reference_temp_c,
                ..DevelopmentParams::default()
            })
            .collect();
        (
            ContactSpec {
                film,
                paper,
                developments,
                exposure_ev: 0.0,
                print_ev: 0.0,
                spectral: false,
                emulsion: true,
                grain: false,
                halation: false,
                couplers: false,
                edge_codes: true,
            },
            geometry,
            pixels,
        )
    }

    #[test]
    fn the_sheet_is_five_strips_on_one_row_of_paper() {
        let geometry = SheetGeometry::new(5, 300.0, Strips::Horizontal);
        let per_mm: f64 = 300.0 / 25.4;
        let px = |mm: f64| (mm * per_mm).round() as usize;
        let strip_w = px(FRAME_W_MM) + px(CUT_MM) * 2;
        let strip_h = px(FRAME_H_MM) + px(REBATE_MM) * 2;
        let gap = px(GAP_MM);
        let margin = px(MARGIN_MM);
        assert_eq!(geometry.width, margin * 2 + strip_w * 3 + gap * 2);
        assert_eq!(geometry.height, margin * 2 + strip_h * 2 + gap);
        assert_eq!(geometry.frames.len(), 5);
        assert_eq!(geometry.frames[0].x, margin + px(CUT_MM));
        assert_eq!(geometry.frames[3].y, margin + strip_h + gap + px(REBATE_MM));
    }

    /// A vertical sheet turns every strip, and keeps the ladder's order.
    ///
    /// The strips are the film's own: 36 mm along and 24 across, so standing
    /// them up swaps those, and the rows still read left to right and top to
    /// bottom. A sheet that ran the ladder up a column instead would be a
    /// picture of a proof, not a proof.
    #[test]
    fn a_vertical_sheet_stands_its_strips_up() {
        let laid = SheetGeometry::new(5, 300.0, Strips::Horizontal);
        let stood = SheetGeometry::new(5, 300.0, Strips::Vertical);
        assert_eq!((stood.frame.0, stood.frame.1), (laid.frame.1, laid.frame.0));
        let (_, _, strip_w, strip_h) = stood.strip_of(&stood.frames[0]);
        assert!(
            strip_h > strip_w,
            "a vertical strip stands up: {strip_w} wide, {strip_h} tall"
        );
        for frame in &stood.frames {
            assert!(frame.height > frame.width, "the frame stands up too");
        }
        // Three strips in the first row, left to right; the fourth starts the
        // next one.
        assert!(stood.frames[0].x < stood.frames[1].x);
        assert_eq!(stood.frames[0].y, stood.frames[1].y);
        assert!(stood.frames[3].y > stood.frames[0].y);
    }

    /// A picture that is bright at the top prints bright at the top of a
    /// vertical frame.
    ///
    /// The frame is laid on the strip a quarter turn one way and the sheet is
    /// turned back the other, and the test is that the two turns cancel: with
    /// both going the same way the photograph would print upside down.
    #[test]
    fn a_vertical_frame_prints_the_way_up() {
        let film = film_stock("kodak_portra_400").expect("film");
        let paper = paper_stock("portra_endura").expect("paper");
        let geometry = SheetGeometry::new(1, 300.0, Strips::Vertical);
        let (width, height) = geometry.frame;
        let mut frame_pixels = vec![[0.02; 3]; width * height];
        for row in 0..height / 4 {
            for x in 0..width {
                frame_pixels[row * width + x] = [0.9; 3];
            }
        }
        let spec = ContactSpec {
            film,
            paper,
            developments: vec![DevelopmentParams {
                time_min: 9.0,
                temp_c: 20.0,
                reference_time_min: film.reference_time_min,
                reference_temp_c: film.reference_temp_c,
                ..DevelopmentParams::default()
            }],
            exposure_ev: 0.0,
            print_ev: 0.0,
            spectral: false,
            emulsion: false,
            grain: false,
            halation: false,
            couplers: false,
            edge_codes: false,
        };
        let contact = print(&frame_pixels, &geometry, &spec);
        let frame = contact.geometry.frames[0];
        let mean = |from: usize, to: usize| {
            let mut sum = 0.0;
            for row in from..to {
                for x in frame.x..frame.x + frame.width {
                    let pixel = contact.pixels[row * contact.geometry.width + x];
                    sum += (pixel[0] + pixel[1] + pixel[2]) / 3.0;
                }
            }
            sum / (frame.width * (to - from)) as f64
        };
        let top = mean(frame.y, frame.y + frame.height / 4);
        let bottom = mean(
            frame.y + frame.height - frame.height / 4,
            frame.y + frame.height,
        );
        assert!(
            top > bottom,
            "the bright band must print at the top of the frame: {top} against {bottom}"
        );
    }

    #[test]
    fn the_margin_is_paper_and_the_rebate_is_not() {
        let (spec, geometry, pixels) = spec(&[3.0, 6.0, 9.0, 12.0, 15.0]);
        let contact = print(&pixels, &geometry, &spec);
        let mean = |colour: [f64; 3]| (colour[0] + colour[1] + colour[2]) / 3.0;
        let corner = contact.pixels[0];
        let (sx, sy, _, _) = contact.geometry.strip_of(&contact.geometry.frames[0]);
        let rebate = contact.pixels[sy * contact.geometry.width + sx];
        assert!(
            mean(corner) > 0.8,
            "the paper margin prints as paper, got {corner:?}"
        );
        assert!(
            mean(rebate) < mean(corner) * 0.6,
            "the clear rebate prints dark, got {rebate:?} against {corner:?}"
        );
    }

    #[test]
    fn the_frames_differ_along_the_ladder() {
        let (spec, geometry, pixels) = spec(&[3.0, 6.0, 9.0, 12.0, 15.0]);
        let contact = print(&pixels, &geometry, &spec);
        let mean = |frame: &FrameRect| {
            let mut sum = 0.0;
            for row in frame.y..frame.y + frame.height {
                for x in frame.x..frame.x + frame.width {
                    let pixel = contact.pixels[row * contact.geometry.width + x];
                    sum += (pixel[0] + pixel[1] + pixel[2]) / 3.0;
                }
            }
            sum / (frame.width * frame.height) as f64
        };
        let first = mean(&contact.geometry.frames[0]);
        let last = mean(&contact.geometry.frames[4]);
        assert!(
            (first - last).abs() > 0.02,
            "five developments of one exposure must not print alike: {first} vs {last}"
        );
    }

    #[test]
    fn a_reversal_is_not_printable() {
        let film = film_stock("provia_100f").expect("film");
        assert!(!printable(film));
    }

    #[test]
    fn the_glyphs_cover_what_an_edge_needs() {
        for character in "KALLOTYPE PORTRA 400 3.0 MIN-".chars() {
            assert!(glyph(character).is_some(), "no glyph for {character:?}");
        }
    }
}
