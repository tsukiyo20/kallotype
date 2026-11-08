#!/usr/bin/env python3
"""Inspect a `.kalofilm` file: verify it, read its header, or export its tables.

Standard library only, so a file can be used on a machine that does not have the
renderer. The format is specified in `../FORMAT.md`; this script is the shortest
correct implementation of it.

    python3 kalofilm.py --check ../fuji-pro400h/fuji-pro400h.kalofilm
    python3 kalofilm.py --csv /tmp fuji-pro400h.kalofilm   # one CSV per table
    python3 kalofilm.py --dump fuji-pro400h.kalofilm       # the raw header

`--csv` writes one file per table, with a column of wavelengths in nanometres
and one column per row — which is the form every plotting tool, spreadsheet and
numerical library can read.
"""

from __future__ import annotations

import argparse
import hashlib
import struct
import sys
import tomllib
from pathlib import Path

MAGIC = b"KALOFILM"
ROWS = {"layers": 3, "dyes": 3, "mask": 1, "cl_sensitivity": 1}
COLUMNS = {
    "layers": ("red_sensitive", "green_sensitive", "blue_sensitive"),
    "dyes": ("cyan", "magenta", "yellow"),
    "mask": ("density",),
    "cl_sensitivity": ("relative_sensitivity",),
}


def read(path: Path) -> tuple[int, dict, bytes]:
    """Version, header and the raw table blob, with the digest checked."""
    raw = path.read_bytes()
    if len(raw) < 48 or raw[:8] != MAGIC:
        raise SystemExit(f"{path}: not a kalofilm file (no KALOFILM magic)")
    version, length = struct.unpack("<II", raw[8:16])
    if version != 1:
        raise SystemExit(f"{path}: version {version}; this script reads version 1")
    if hashlib.sha256(raw[:-32]).digest() != raw[-32:]:
        raise SystemExit(f"{path}: digest mismatch — the file is truncated or altered")
    return version, tomllib.loads(raw[16 : 16 + length].decode()), raw[16 + length : -32]


def tables(header: dict, blob: bytes) -> list[tuple[str, list[list[float]]]]:
    """The blob as named tables of rows, in file order."""
    length = header["grid"]["len"]
    at = 0
    found = []
    for name in header["tables"]:
        if name not in ROWS:
            raise SystemExit(f"unknown table `{name}`")
        rows = []
        for _ in range(ROWS[name]):
            rows.append(list(struct.unpack(f"<{length}d", blob[at : at + length * 8])))
            at += length * 8
        found.append((name, rows))
    if at != len(blob):
        raise SystemExit(f"{len(blob) - at} bytes of tables are not in the directory")
    return found


def check(path: Path) -> int:
    version, header, blob = read(path)
    found = tables(header, blob)
    print(f"{header['label']}  ({header['process']})  schema {header['schema']}")
    print(f"  version {version}, {len(blob)} bytes of tables, digest ok")
    provenance = header["provenance"]
    print(f"  from {provenance['publication']} page {provenance['page']}, "
          f"retrieved {provenance['retrieved']}")
    print("  measured:")
    for key, value in header["measured"].items():
        print(f"    {key:12s} {value}")
    print(f"  tables: {[(name, len(rows)) for name, rows in found]}")
    return 0


def export(path: Path, directory: Path) -> int:
    _, header, blob = read(path)
    grid = header["grid"]
    wavelengths = [
        grid["start_nm"] + grid["step_nm"] * index for index in range(grid["len"])
    ]
    directory.mkdir(parents=True, exist_ok=True)
    for name, rows in tables(header, blob):
        target = directory / f"{header['id']}_{name}.csv"
        with target.open("w") as handle:
            handle.write("wavelength_nm," + ",".join(COLUMNS[name]) + "\n")
            for index, wavelength in enumerate(wavelengths):
                values = ",".join(f"{row[index]:.6f}" for row in rows)
                handle.write(f"{wavelength:.0f},{values}\n")
        print(f"{target}  {len(rows)} rows, {len(wavelengths)} points")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("file", type=Path)
    parser.add_argument("--check", action="store_true", help="verify and summarise (default)")
    parser.add_argument("--dump", action="store_true", help="print the raw TOML header")
    parser.add_argument("--csv", type=Path, metavar="DIR", help="write one CSV per table")
    options = parser.parse_args()

    if options.dump:
        _, header_length = struct.unpack("<II", options.file.read_bytes()[8:16])
        raw = options.file.read_bytes()
        print(raw[16 : 16 + header_length].decode())
        return 0
    if options.csv:
        return export(options.file, options.csv)
    return check(options.file)


if __name__ == "__main__":
    sys.exit(main())
