#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "boto3>=1.43",
#     "ruamel.yaml",
# ]
# ///
"""Emit a JSON matrix of Packer templates for a given lifecycle.

Each entry includes the runner label and arch-specific install/build args.

Usage:
    matrix.py <lifecycle>                # pinned | rolling | corpus
    matrix.py all                        # every lifecycle, concatenated
    matrix.py <lifecycle> --skip-built   # drop pinned/corpus rows whose hash already exists in the image bucket
"""

import argparse
import json
import sys
from pathlib import Path

import hash
import storage
from ruamel.yaml import YAML

REPO_ROOT = Path(__file__).resolve().parent.parent
TEMPLATES_ROOT = REPO_ROOT / "templates"

LIFECYCLES = ("pinned", "rolling", "corpus")

RUNNER_CONFIG = {
    "default": {
        "runner": "ubuntu-latest",
        "packages": "qemu-system-x86 qemu-utils cloud-image-utils ovmf",
        "args": "",
    },
    "macos": {
        "runner": "macos-26",
        "packages": "qemu cirruslabs/cli/tart",
        "args": "",
    },
}


def discover(lifecycle: str) -> list[dict]:
    yaml = YAML(typ="safe")
    lifecycle_dir = TEMPLATES_ROOT / lifecycle
    if not lifecycle_dir.is_dir():
        return []

    entries = []
    for sidecar in sorted(lifecycle_dir.rglob("image.yml")):
        meta = yaml.load(sidecar)
        arch = meta.get("arch", "amd64")
        runner = meta.get("runner", "default")
        if runner not in RUNNER_CONFIG:
            print(f"{sidecar}: unsupported runner {runner!r}, skipping", file=sys.stderr)
            continue

        if "markers" in meta and "ciskip" in meta["markers"]:
            print(f"{sidecar}: marked ciskip, skipping", file=sys.stderr)
            continue

        template = f"{lifecycle}/{sidecar.parent.name}"
        cfg = RUNNER_CONFIG[runner]
        entries.append(
            {
                "template": template,
                "lifecycle": lifecycle,
                "arch": arch,
                "runner": cfg["runner"],
                "packages": cfg["packages"],
                "args": cfg["args"],
            }
        )
    return entries


def _filter_built(entries: list[dict]) -> list[dict]:
    kept = []
    for entry in entries:
        # Rolling versions are date-stamped, so every run is unique
        if entry["lifecycle"] == "rolling":
            kept.append(entry)
            continue

        version = hash.compute(TEMPLATES_ROOT / entry["template"])
        if storage.exists(entry["template"], version):
            print(f"{entry['template']}: already built ({version}), skipping", file=sys.stderr)
            continue

        kept.append(entry)

    return kept


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("lifecycle", choices=(*LIFECYCLES, "all"), help="which templates to include")
    parser.add_argument(
        "--skip-built",
        action="store_true",
        help="drop pinned/corpus rows whose content hash already exists in the bucket",
    )
    args = parser.parse_args()

    if args.lifecycle == "all":
        out = [entry for lc in LIFECYCLES for entry in discover(lc)]
    else:
        out = discover(args.lifecycle)

    if args.skip_built:
        out = _filter_built(out)

    print(json.dumps(out))
