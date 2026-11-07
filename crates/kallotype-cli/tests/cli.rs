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
        "c41_standard",
        "c41_contrast",
        "bw_classic",
        "c41_paper",
        "bw_paper",
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
    // Q10 = 2: ten degrees warmer halves the time for the same result.
    let warm_short = stdout(&run(&["curve", "--dev", "3.25", "--temp", "30"]));
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

/// Without the feature the flag still exists, so the answer is a sentence
/// instead of clap's "unexpected argument".
#[cfg(not(feature = "gpu"))]
#[test]
fn gpu_asks_for_a_build_that_has_one() {
    let dir = scratch("gpu-off");
    let output = kalo()
        .arg("render")
        .arg(chart())
        .arg("-o")
        .arg(dir.join("out.png"))
        .arg("--gpu")
        .output()
        .expect("kalo should start");
    assert!(!output.status.success(), "the render should be refused");
    let message = stderr(&output);
    assert!(message.contains("--features gpu"), "{message}");
}

/// With the feature the render has to succeed whether or not there is an
/// adapter: a missing GPU is a warning and a CPU render, not a failure.
#[cfg(feature = "gpu")]
#[test]
fn gpu_renders_or_falls_back_and_says_which() {
    let dir = scratch("gpu-on");
    let out = dir.join("out.png");
    let output = kalo()
        .arg("render")
        .arg(chart())
        .arg("-o")
        .arg(&out)
        .args(["--dev", "9", "--gpu"])
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
