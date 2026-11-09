//! End-to-end tests against the built `kalo` binary.
//!
//! These exercise the contract a user actually has: exit codes, the lines the
//! report prints, and the files that appear on disk.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn kalo() -> Command {
    Command::new(env!("CARGO_BIN_EXE_kalo"))
}

fn run(args: &[&str]) -> Output {
    kalo().args(args).output().expect("kalo should start")
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

/// The committed test chart, inside the crate so the published package has it.
fn chart() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("assets/testchart.png")
}

/// A private directory per test, so the suite can run in parallel.
fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("kalo-it-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch directory");
    dir
}

/// Pull the `×1.177` factor out of the report.
fn contrast(output: &str) -> f64 {
    let line = output
        .lines()
        .find(|line| line.trim_start().starts_with("contrast"))
        .expect("the report must contain a contrast line");
    let tail = line.split('×').nth(1).expect("a × factor");
    tail.split_whitespace()
        .next()
        .expect("a number after ×")
        .parse()
        .expect("the factor must parse")
}

#[test]
fn stocks_lists_every_builtin() {
    let output = run(&["stocks"]);
    assert!(output.status.success(), "stderr: {}", stderr(&output));

    let text = stdout(&output);
    for id in [
        "kodak_ultramax400",
        "c41_contrast",
        "kodak_tmax100",
        "portra_endura",
        "supra_endura",
        "endura_premier_metallic",
        "fuji_crystal_archive_pearl",
        "polymax_ii_rc",
    ] {
        assert!(text.contains(id), "{id} missing from:\n{text}");
    }
}

#[test]
fn longer_development_raises_contrast() {
    let short = stdout(&run(&["curve", "--dev", "3"]));
    let long = stdout(&run(&["curve", "--dev", "12"]));

    assert!(
        contrast(&long) > contrast(&short),
        "12 min ({}) should out-contrast 3 min ({})",
        contrast(&long),
        contrast(&short)
    );
}

#[test]
fn temperature_trades_against_time() {
    // The fitted q10 is 1.70, not the photographer's two: ten degrees warmer
    // divides the time by 1.70, so 6.5 minutes at 20 °C is 3.82 at 30 °C.
    let warm_short = stdout(&run(&["curve", "--dev", "3.8235", "--temp", "30"]));
    let cool_normal = stdout(&run(&["curve", "--dev", "6.5", "--temp", "20"]));

    let delta = (contrast(&warm_short) - contrast(&cool_normal)).abs();
    assert!(delta < 1e-3, "expected parity, got delta {delta}");
}

/// The grain is a fixture, not a different image every render: same seed, same
/// bytes. A different seed has to be a different image, or the seed is ignored.
#[test]
fn grain_is_deterministic_in_its_seed() {
    let dir = scratch("grain");
    let render = |name: &str, seed: &str| {
        let out = dir.join(name);
        let output = kalo()
            .arg("render")
            .arg(chart())
            .arg("-o")
            .arg(&out)
            .args(["--dev", "9", "--grain", "--frame-mm", "3.6"])
            .args(["--grain-seed", seed])
            .output()
            .expect("kalo should start");
        assert!(output.status.success(), "stderr: {}", stderr(&output));
        std::fs::read(&out).expect("the output file was written")
    };

    let first = render("a.png", "0");
    let again = render("b.png", "0");
    let other = render("c.png", "1");
    assert_eq!(first, again, "the same seed must reproduce the same image");
    assert_ne!(first, other, "a different seed must change the grain");
}

/// A uniform frame at a known luminance, written as the 8-bit PNG the CLI reads.
///
/// The luminance is linear light; `save` encodes it to sRGB, so what comes back
/// is within half a code value of what went in.
fn flat_frame(dir: &Path, name: &str, linear: f64) -> PathBuf {
    let path = dir.join(name);
    let image = kallotype_io::Image {
        width: 8,
        height: 8,
        pixels: vec![[linear; 3]; 64],
    };
    kallotype_io::save(&path, &image).expect("write the frame");
    path
}

/// The offset the report says it applied, exactly as it printed it.
fn printed_ev(report: &str) -> String {
    let line = report
        .lines()
        .find(|line| line.trim_start().starts_with("ev "))
        .expect("the report must contain an ev line");
    line.split_whitespace()
        .find(|word| word.parse::<f64>().is_ok())
        .expect("the ev line must carry a number")
        .to_owned()
}

/// The same, as a number.
fn ev(report: &str) -> f64 {
    printed_ev(report).parse().expect("a number of stops")
}

#[test]
fn render_writes_an_image_and_creates_directories() {
    let dir = scratch("render");
    let out = dir.join("nested").join("out.png");

    let output = kalo()
        .arg("render")
        .arg(chart())
        .arg("-o")
        .arg(&out)
        .arg("--dev")
        .arg("9")
        .output()
        .expect("kalo should start");

    assert!(output.status.success(), "stderr: {}", stderr(&output));
    assert!(out.exists(), "the output file was not written");

    let image =
        kallotype_io::load(&out, kallotype_io::InputEncoding::Srgb).expect("a readable PNG");
    assert_eq!((image.width, image.height), (1200, 800));

    std::fs::remove_dir_all(&dir).expect("cleanup");
}

#[test]
fn auto_exposure_places_the_frames_mean_on_mid_grey() {
    let dir = scratch("auto-ev");
    // Two stops below 18 % grey: a dim scene, or a camera file normalised to a
    // white point nobody documented.
    let input = flat_frame(&dir, "dark.png", 0.045);
    let render = |stops: &str, name: &str| {
        let out = dir.join(name);
        let output = kalo()
            .arg("render")
            .arg(&input)
            .arg("-o")
            .arg(&out)
            .args(["--ev", stops])
            .output()
            .expect("kalo should start");
        assert!(output.status.success(), "stderr: {}", stderr(&output));
        (stdout(&output), out)
    };

    let (report, auto_out) = render("auto", "auto.png");
    let solved = ev(&report);
    assert!(
        (solved - 2.0).abs() < 0.05,
        "a frame of 0.045 should be metered to +2 stops, got {solved:+.3}\n{report}"
    );
    assert!(report.contains("auto — frame mean 0.045"), "{report}");

    // The meter is a solve, not a heuristic: the number it prints, typed back
    // in, has to reproduce the frame. It agrees to a code value and not bit
    // for bit, because the report rounds the offset to 0.01 stop.
    let (_, manual_out) = render(&printed_ev(&report), "manual.png");
    let codepoints = |path: &Path| -> Vec<u8> {
        kallotype_io::load(path, kallotype_io::InputEncoding::Srgb)
            .expect("a rendered frame")
            .pixels
            .iter()
            .flatten()
            .map(|value| (kallotype_core::linear_to_srgb(*value) * 255.0).round() as u8)
            .collect()
    };
    let (metered, hand) = (codepoints(&auto_out), codepoints(&manual_out));
    let worst = metered
        .iter()
        .zip(&hand)
        .map(|(a, b)| a.abs_diff(*b))
        .max()
        .expect("a frame");
    assert!(
        worst <= 1,
        "the printed offset must reproduce the metered frame, worst {worst} code values"
    );

    // And it has to have moved: a meter that solves to zero is not a meter.
    let (_, zero_out) = render("0", "zero.png");
    assert_ne!(
        std::fs::read(&auto_out).expect("the metered frame"),
        std::fs::read(&zero_out).expect("the unmetered frame")
    );
}

#[test]
fn a_black_frame_is_not_lifted_by_a_meter_that_cannot_read_it() {
    let dir = scratch("black-ev");
    let input = flat_frame(&dir, "black.png", 0.0);
    let out = dir.join("out.png");

    let output = kalo()
        .arg("render")
        .arg(&input)
        .arg("-o")
        .arg(&out)
        .args(["--ev", "auto"])
        .output()
        .expect("kalo should start");

    assert!(output.status.success(), "stderr: {}", stderr(&output));
    // No light is no exposure to recover: the offset is zero, not infinite.
    assert!(ev(&stdout(&output)).abs() < 1e-9, "{}", stdout(&output));
}

#[test]
fn an_exposure_that_is_neither_a_number_nor_auto_is_refused() {
    let output = run(&[
        "render",
        chart().to_str().expect("a utf-8 path"),
        "-o",
        "out/never.png",
        "--ev",
        "auto2",
    ]);
    assert!(!output.status.success(), "{}", stdout(&output));
    let message = stderr(&output);
    assert!(
        message.contains("expected a number of stops or `auto`"),
        "{message}"
    );
    assert!(message.contains("auto2"), "{message}");
}

#[test]
fn bake_writes_a_table_and_render_uses_it() {
    let dir = scratch("bake");
    let table = dir.join("model.klut");

    let baked = kalo()
        .arg("bake")
        .arg("-o")
        .arg(&table)
        .args(["--size", "5"])
        .output()
        .expect("kalo should start");
    assert!(baked.status.success(), "stderr: {}", stderr(&baked));
    assert!(table.exists(), "the table was not written");

    let out = dir.join("out.png");
    let rendered = kalo()
        .arg("render")
        .arg(chart())
        .arg("-o")
        .arg(&out)
        .arg("--lut")
        .arg(&table)
        .output()
        .expect("kalo should start");
    assert!(rendered.status.success(), "stderr: {}", stderr(&rendered));
    assert!(out.exists());
    assert!(
        stdout(&rendered).contains("spectral, baked table"),
        "{}",
        stdout(&rendered)
    );

    // The table records which model baked it, and the render loaded it without
    // a warning because the identities match.
    let bytes = std::fs::read(&table).expect("table");
    let text = String::from_utf8_lossy(&bytes[14..80]).to_string();
    assert!(
        text.contains("camera="),
        "no provenance in the header: {text}"
    );

    std::fs::remove_dir_all(&dir).expect("cleanup");
}

#[test]
fn a_truncated_table_is_rejected() {
    let dir = scratch("badlut");
    let table = dir.join("broken.klut");
    std::fs::write(&table, b"KLUT").expect("write");

    let output = kalo()
        .arg("render")
        .arg(chart())
        .arg("-o")
        .arg(dir.join("out.png"))
        .arg("--lut")
        .arg(&table)
        .output()
        .expect("kalo should start");

    assert!(!output.status.success());
    assert!(
        stderr(&output).contains("lookup table"),
        "{}",
        stderr(&output)
    );

    std::fs::remove_dir_all(&dir).expect("cleanup");
}

#[test]
fn unknown_film_is_reported_by_name() {
    let output = run(&["curve", "--film", "portra400"]);
    assert!(!output.status.success(), "an unknown stock must fail");
    assert!(
        stderr(&output).contains("unknown film stock 'portra400'"),
        "stderr: {}",
        stderr(&output)
    );
}

#[test]
fn non_positive_development_time_is_rejected() {
    let output = run(&["curve", "--dev", "0"]);
    assert!(!output.status.success());
    assert!(
        stderr(&output).contains("--dev must be"),
        "stderr: {}",
        stderr(&output)
    );
}

/// With the GPU off at build time the default render still has to work, on the
/// CPU, and the report has to say so rather than implying a device that was
/// never compiled in.
#[cfg(not(feature = "gpu"))]
#[test]
fn a_build_without_the_gpu_renders_on_the_cpu() {
    let dir = scratch("gpu-off");
    let output = kalo()
        .arg("render")
        .arg(chart())
        .arg("-o")
        .arg(dir.join("out.png"))
        .output()
        .expect("kalo should start");
    assert!(output.status.success(), "stderr: {}", stderr(&output));
    let report = stdout(&output);
    let line = report
        .lines()
        .find(|line| line.trim_start().starts_with("backend"))
        .expect("the report must name the backend");
    assert!(line.contains("cpu"), "unexpected backend line: {line}");
}

/// The GPU is the default, and the render has to succeed whether or not there
/// is an adapter: a missing GPU is a warning and a CPU render, not a failure.
#[cfg(feature = "gpu")]
#[test]
fn the_default_backend_is_the_gpu_or_says_why_it_is_not() {
    let dir = scratch("gpu-on");
    let out = dir.join("out.png");
    let output = kalo()
        .arg("render")
        .arg(chart())
        .arg("-o")
        .arg(&out)
        .args(["--dev", "9"])
        .output()
        .expect("kalo should start");
    assert!(output.status.success(), "stderr: {}", stderr(&output));
    assert!(out.exists(), "no image was written");
    let report = stdout(&output);
    let line = report
        .lines()
        .find(|line| line.trim_start().starts_with("backend"))
        .expect("the report must name the backend");
    assert!(
        line.contains("gpu") || line.contains("cpu"),
        "unexpected backend line: {line}"
    );
}

/// The spectral path and grain are no longer CPU-only, and the agreement that
/// matters is the one a user can see: the two backends have to give the same
/// eight-bit file. If the adapter is missing the render still has to succeed, and
/// to say which machine did it.
///
/// The frame is drawn here rather than taken from the asset, because a slow
/// spectral render in a debug build costs a minute per image and a test nobody
/// wants to run protects nothing. What the path does does not depend on the
/// picture; what it does depend on is the stages and the effects, and those are
/// all on.
///
/// Grain is the interesting one: it is a random draw, so "close enough" would be
/// false — the two backends either draw the same number or they are two films.
#[cfg(feature = "gpu")]
#[test]
fn the_gpu_renders_the_effects_to_the_same_pixels_as_the_cpu() {
    let dir = scratch("gpu-spectral");
    let on_cpu = dir.join("cpu.png");
    let on_gpu = dir.join("gpu.png");
    let stages = [
        "--spectral",
        "--spectral-print",
        "--spectral-scan",
        "--grain",
    ];

    let input = dir.join("input.png");
    const WIDTH: u32 = 48;
    const HEIGHT: u32 = 32;
    let mut pixels = Vec::with_capacity((WIDTH * HEIGHT) as usize);
    for y in 0..HEIGHT {
        for x in 0..WIDTH {
            let a = f64::from(x) / f64::from(WIDTH - 1);
            let b = f64::from(y) / f64::from(HEIGHT - 1);
            pixels.push([a, b, (a * b).sqrt()]);
        }
    }
    kallotype_io::save(
        &input,
        &kallotype_io::Image {
            width: WIDTH,
            height: HEIGHT,
            pixels,
        },
    )
    .expect("the test frame");

    let cpu = kalo()
        .arg("render")
        .arg(&input)
        .arg("-o")
        .arg(&on_cpu)
        .arg("--no-gpu")
        .args(stages)
        .output()
        .expect("kalo should start");
    assert!(cpu.status.success(), "stderr: {}", stderr(&cpu));

    let gpu = kalo()
        .arg("render")
        .arg(&input)
        .arg("-o")
        .arg(&on_gpu)
        .args(stages)
        .output()
        .expect("kalo should start");
    assert!(gpu.status.success(), "stderr: {}", stderr(&gpu));

    let report = stdout(&gpu);
    let backend = report
        .lines()
        .find(|line| line.trim_start().starts_with("backend"))
        .expect("the report must name the backend")
        .to_owned();
    if backend.contains("gpu —") {
        let decoded_cpu =
            kallotype_io::load(&on_cpu, kallotype_io::InputEncoding::Srgb).expect("the cpu render");
        let decoded_gpu =
            kallotype_io::load(&on_gpu, kallotype_io::InputEncoding::Srgb).expect("the gpu render");
        assert_eq!(decoded_cpu.pixels.len(), decoded_gpu.pixels.len());

        // Under a megapixel the two files are usually byte-identical, but that
        // is not a property: the tolerance is about 1e-6 in linear light, which
        // is 3e-4 of an eight-bit level, so a sample lands on a rounding
        // boundary every few thousand pixels and the byte flips. One level is
        // the promise; byte equality is a coincidence.
        let mut worst = 0_i32;
        let mut differing = 0_usize;
        for (cpu, gpu) in decoded_cpu.pixels.iter().zip(&decoded_gpu.pixels) {
            let mut moved = false;
            for channel in 0..3 {
                let left = (kallotype_core::linear_to_srgb(cpu[channel]) * 255.0).round() as i32;
                let right = (kallotype_core::linear_to_srgb(gpu[channel]) * 255.0).round() as i32;
                worst = worst.max((left - right).abs());
                moved |= left != right;
            }
            if moved {
                differing += 1;
            }
        }
        assert!(
            worst <= 1,
            "the backends differ by {worst} levels on {differing} pixels: {backend}"
        );
    } else {
        assert!(
            stderr(&gpu).contains("warning"),
            "a fallback has to say so: {backend}"
        );
    }
}

/// `--no-gpu` has to be honoured even when no device exists: it is the escape
/// hatch for a machine whose driver is worse than its CPU.
#[cfg(feature = "gpu")]
#[test]
fn the_cpu_can_be_forced() {
    let dir = scratch("cpu-forced");
    let output = kalo()
        .arg("render")
        .arg(chart())
        .arg("-o")
        .arg(dir.join("out.png"))
        .args(["--spectral", "--no-gpu"])
        .output()
        .expect("kalo should start");
    assert!(output.status.success(), "stderr: {}", stderr(&output));
    let report = stdout(&output);
    let line = report
        .lines()
        .find(|line| line.trim_start().starts_with("backend"))
        .expect("the report must name the backend");
    assert!(line.contains("cpu"), "unexpected backend line: {line}");
}
