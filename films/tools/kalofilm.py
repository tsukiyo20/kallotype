#!/usr/bin/env python3
"""Read and check a `.kalofilm` file — the format in ../FORMAT.md.

No dependencies beyond the standard library, so a file can be inspected on a
machine that does not have the renderer.

    python3 kalofilm.py ../fuji-pro400h/fuji-pro400h.kalofilm
    python3 kalofilm.py --dump ../provia-100f/provia-100f.kalofilm > header.toml
"""

from __future__ import annotations

import argparse
import hashlib
import struct
import sys
import tomllib

MAGIC = b"KALOFILM"


def read(path):
    raw = open(path, "rb").read()
    if len(raw) < 48 or raw[:8] != MAGIC:
        raise SystemExit("not a kalofilm file")
    version, length = struct.unpack("<II", raw[8:16])
    header_end = 16 + length
    header = tomllib.loads(raw[16:header_end].decode())
    tables = raw[header_end:-32]
    if hashlib.sha256(raw[:-32]).digest() != raw[-32:]:
        raise SystemExit("digest mismatch: the file is truncated or altered")
    return version, header, tables


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("file")
    parser.add_argument("--dump", action="store_true", help="print the raw header")
    options = parser.parse_args()

    version, header, tables = read(options.file)
    if options.dump:
        print(header_to_toml(options.file))
        return 0

    print(f"{header['label']}  ({header['process']})  schema {header['schema']}")
    print(f"  version {version}, {len(tables)} bytes of tables, digest ok")
    provenance = header["provenance"]
    print(f"  from {provenance['publication']} page {provenance['page']}, "
          f"retrieved {provenance['retrieved']}")
    print("  measured:")
    for key, value in header["measured"].items():
        print(f"    {key:11s} {value}")
    expected = sum(table["rows"] * header["grid"]["len"] * 8 for table in header["tables"])
    print(f"  tables: {[table['name'] for table in header['tables']]} "
          f"({len(tables)} bytes, expected {expected})")
    if len(tables) != expected:
        raise SystemExit("table blob does not match the directory")
    return 0


def header_to_toml(path) -> str:
    raw = open(path, "rb").read()
    length = struct.unpack("<I", raw[12:16])[0]
    return raw[16 : 16 + length].decode()


if __name__ == "__main__":
    sys.exit(main())
