#!/usr/bin/env python3
"""Turn the icon master into every platform's assets.

The master is `kallo-icon-1024.png`, a full-bleed square rendered from
`kallo-icon.svg`. This script owns the platform differences: macOS wants a
rounded square with a transparent margin, iOS wants the full square and no
alpha, Android wants adaptive layers, Windows wants one ICO.

Run from anywhere:

    python3 app/icon/generate.py

Pillow is the only dependency.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(__file__).resolve().parent
MASTER = SOURCE / "kallo-icon-1024.png"

MACOS = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
IOS = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
ANDROID = ROOT / "android/app/src/main/res"
WINDOWS = ROOT / "windows/runner/resources/app_icon.ico"

MAC_SIZES = {
    16: "app_icon_16.png",
    32: "app_icon_32.png",
    64: "app_icon_64.png",
    128: "app_icon_128.png",
    256: "app_icon_256.png",
    512: "app_icon_512.png",
    1024: "app_icon_1024.png",
}

# Android's legacy mipmaps, in pixels.
ANDROID_LEGACY = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# Adaptive icon layers are 108 dp; the visible window is 72 dp and the safe
# zone is 66 dp. The artwork is scaled down so the frame sits inside it.
ANDROID_ADAPTIVE = {
    "drawable-mdpi": 108,
    "drawable-hdpi": 162,
    "drawable-xhdpi": 216,
    "drawable-xxhdpi": 324,
    "drawable-xxxhdpi": 432,
}


def squircle(master: Image.Image, margin: int = 100, radius: int = 185) -> Image.Image:
    """The macOS icon: a rounded square on transparent canvas, with its shadow."""
    size = master.width
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow)
    draw.rounded_rectangle(
        (margin, margin + 14, size - margin, size - margin + 14),
        radius=radius,
        fill=(0, 0, 0, 90),
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(24)))

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (margin, margin, size - margin, size - margin),
        radius=radius,
        fill=255,
    )
    shape = master.copy()
    shape.putalpha(mask)
    canvas.alpha_composite(shape)
    return canvas


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG", optimize=True)


def macos(master: Image.Image) -> None:
    icon = squircle(master)
    for size, name in MAC_SIZES.items():
        save_png(icon.resize((size, size), Image.LANCZOS), MACOS / name)


def ios(master: Image.Image) -> None:
    full = master.convert("RGB")
    contents = json.loads((IOS / "Contents.json").read_text())
    for entry in contents["images"]:
        filename = entry.get("filename")
        if not filename:
            continue
        points = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        size = round(points * scale)
        full.resize((size, size), Image.LANCZOS).save(
            IOS / filename,
            "PNG",
            optimize=True,
        )


def android(master: Image.Image) -> None:
    full = master.convert("RGB")
    for folder, size in ANDROID_LEGACY.items():
        (ANDROID / folder).mkdir(parents=True, exist_ok=True)
        full.resize((size, size), Image.LANCZOS).save(
            ANDROID / folder / "ic_launcher.png",
            "PNG",
            optimize=True,
        )

    # The launcher masks the background layer; keep the frame inside its 66 dp
    # safe zone by shrinking the whole square a little.
    for folder, size in ANDROID_ADAPTIVE.items():
        (ANDROID / folder).mkdir(parents=True, exist_ok=True)
        layer = Image.new("RGB", (size, size), (7, 7, 8))
        art = full.resize((round(size * 0.90),) * 2, Image.LANCZOS)
        layer.paste(art, ((size - art.width) // 2, (size - art.height) // 2))
        layer.save(
            ANDROID / folder / "ic_launcher_background.png",
            "PNG",
            optimize=True,
        )


def windows(master: Image.Image) -> None:
    icon = squircle(master, margin=72, radius=200)
    icon.save(
        WINDOWS,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )


def main() -> None:
    master = Image.open(MASTER).convert("RGBA")
    if master.size != (1024, 1024):
        raise SystemExit(f"{MASTER} is not 1024 x 1024")
    macos(master)
    ios(master)
    android(master)
    windows(master)
    print("icons written from", MASTER)


if __name__ == "__main__":
    main()
