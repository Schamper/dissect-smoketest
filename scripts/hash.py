#!/usr/bin/env python3
"""Compute a deterministic content hash for a Packer template directory.

Usage:
    hash.py <template-dir>

The hash inputs are every regular file under the directory, hashed in sorted
POSIX-path order with the relative path included (so renames change the hash).
"""

import hashlib
import sys
from pathlib import Path

HASH_LEN = 16


def compute(template_dir: Path) -> str:
    template_dir = template_dir.resolve()
    if not template_dir.is_dir():
        raise SystemExit(f"not a directory: {template_dir}")

    files = sorted(p for p in template_dir.rglob("*") if p.is_file())
    h = hashlib.sha256()
    for f in files:
        rel = f.relative_to(template_dir).as_posix()
        h.update(rel.encode())
        h.update(b"\x00")
        h.update(f.read_bytes())
        h.update(b"\x00")
    return h.hexdigest()[:HASH_LEN]


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: hash.py <template-dir>")
    print(compute(Path(sys.argv[1])))
