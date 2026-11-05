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

/// The committed test chart, addressed from the crate directory.
fn chart() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets/testchart.png")
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
