#!/usr/bin/env python3
"""Objective checks on the running model, without reference photographs.

The digitisation is checked where it is made: `kalo stock check` re-derives every
curve from the stored points and the reports quote the residuals. What those
checks cannot see is the *pipeline* — whether a curve survives the exposure, the
print balance, the paper and the conversion back to sRGB. This script renders a
known synthetic chart through every stock and measures properties that must
hold whatever the film is:

- **the print balance.** An 18 % grey patch must come back as an 18 % grey
  patch, neutral to the byte. The model solves the enlarger exposure for
  exactly this; a stock that misses it has a broken curve, mask or paper pair.
- **monotonicity.** A nine-step grey ramp must come out non-decreasing. An
  inversion is a sign error, a clamped tone, or a channel swap.
- **development.** Rendering the same chart at 4, 8 and 16 minutes must raise
  the contrast monotonically. The curve-against-time fit is checked on data
  elsewhere; this checks that the fit reaches the render.
- **path divergence.** The scalar and the spectral print are two descriptions of
  the same film. They agree at mid grey by construction and differ away from it;
  the script reports the mean distance rather than passing judgement, because the
  number is a property of the approximation and a number that moves is worth
  knowing. Run with `--spectral --spectral-print`, since `--spectral` alone only
  changes the exposure path and leaves the print scalar.

Requires numpy and Pillow, and a built `kalo` (without the `raw` feature is
fine — nothing here decodes a camera raw).

Usage:

    python3 tools/eval.py                 # every film, then every paper
    KALO=target/release/kalo python3 tools/eval.py

Exit status is 1 if a hard check fails, which makes it usable as a regression
test; the divergence column is informational.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent

# Nine steps across the print's range, including a patch at linear 0.18 (sRGB
# 118) — the value the print balance is solved for.
STEPS = [0, 36, 72, 109, 118, 145, 182, 219, 255]
PATCH = 40
MID = 4  # index of the 0.18 patch in STEPS


def ramp(path: Path) -> None:
    image = Image.new("RGB", (len(STEPS) * PATCH, PATCH))
    pixels = image.load()
    for index, value in enumerate(STEPS):
        for x in range(index * PATCH, (index + 1) * PATCH):
            for y in range(PATCH):
                pixels[x, y] = (value, value, value)
    image.save(path)


def patches(path: Path) -> np.ndarray:
    data = np.asarray(Image.open(path).convert("RGB"), dtype=float)
    return np.array(
        [data[:, index * PATCH + PATCH // 2].mean(axis=0) for index in range(len(STEPS))]
    )


def luma(rgb: np.ndarray) -> float:
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]


def stocks(kalo: str) -> tuple[list[str], list[str]]:
    out = subprocess.run([kalo, "stocks"], capture_output=True, text=True, check=True).stdout
    films, papers, section = [], [], None
    for line in out.splitlines():
        if line.startswith("film stocks"):
            section = "film"
            continue
        if line.startswith("paper stocks"):
            section = "paper"
            continue
        # An entry is indented two spaces; its note is indented further.
        if line.startswith("  ") and not line.startswith("    ") and line.strip() and section:
            name = line.strip().split()[0]
            (films if section == "film" else papers).append(name)
    return films, papers


def render(kalo: str, source: Path, target: Path, *args: str) -> np.ndarray:
    subprocess.run(
        [kalo, "render", str(source), "-o", str(target), *args],
        check=True,
        capture_output=True,
    )
    return patches(target)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--kalo", default=os.environ.get("KALO", str(ROOT / "target/release/kalo")))
    parser.add_argument("--film", default="kodak_portra_400", help="the film for the paper table")
    options = parser.parse_args()

    films, papers = stocks(options.kalo)
    failures = 0
    with tempfile.TemporaryDirectory() as scratch:
        work = Path(scratch)
        chart = work / "ramp.png"
        ramp(chart)

        print(f"{'film':22s} {'mid':>4s} {'neutral':>7s} {'mono':>5s} {'dev 4/8/16':>18s} {'paths':>7s}")
        for film in films:
            base = render(options.kalo, chart, work / "a.png", "--film", film)
            low = render(options.kalo, chart, work / "b.png", "--film", film, "--dev", "4")
            high = render(options.kalo, chart, work / "c.png", "--film", film, "--dev", "16")
            spectral = render(
                options.kalo, chart, work / "d.png", "--film", film,
                "--spectral", "--spectral-print",
            )
            # A reversal is its own picture: --paper does nothing, and the
            # print-balance invariant does not apply to it.
            other_paper = render(
                options.kalo, chart, work / "e.png", "--film", film, "--paper", "c41_paper"
            )
            reversal = np.array_equal(base, other_paper)
            mid = base[MID]
            neutral = float(np.abs(mid - mid.mean()).max())
            luma_series = [luma(base[index]) for index in range(len(STEPS))]
            mono = all(b >= a - 0.5 for a, b in zip(luma_series, luma_series[1:]))
            contrasts = [float(np.std([luma(p) for p in table])) for table in (low, base, high)]
            rising = contrasts[0] < contrasts[1] < contrasts[2]
            divergence = float(np.abs(base - spectral).mean())

            ok_mid = abs(luma(mid) - 118) <= 2 and neutral <= 1
            ok_dev = rising and (contrasts[2] - contrasts[0]) > 1.0
            ok = mono and ok_dev and (reversal or ok_mid)
            status = "ok" if ok else "FAIL"
            if reversal:
                neutral_text = "  n/a"
            else:
                neutral_text = f"{neutral:7.1f}"
            if status == "FAIL":
                failures += 1
            print(
                f"{film:22s} {luma(mid):4.0f}{neutral_text:>7s} {str(mono):>5s} "
                f"{contrasts[0]:5.1f}/{contrasts[1]:5.1f}/{contrasts[2]:5.1f} "
                f"{divergence:7.2f}  {status}"
            )

        print()
        print(f"{'paper':22s} {'mid':>4s} {'neutral':>7s} {'contrast':>8s}")
        for paper in papers:
            table = render(
                options.kalo, chart, work / "e.png", "--film", options.film, "--paper", paper
            )
            mid = table[MID]
            neutral = float(np.abs(mid - mid.mean()).max())
            contrast = float(np.std([luma(p) for p in table]))
            ok = abs(luma(mid) - 118) <= 3 and neutral <= 2
            if not ok:
                failures += 1
            print(f"{paper:22s} {luma(mid):4.0f} {neutral:7.1f} {contrast:8.1f}  {'ok' if ok else 'FAIL'}")

    print()
    print("ok" if failures == 0 else f"{failures} check(s) failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
