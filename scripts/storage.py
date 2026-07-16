#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "boto3>=1.43",
#     "ruamel.yaml",
# ]
# ///
"""Image store helper.

Reads connection info from the environment:
    AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY    — Access keys
    S3_ENDPOINT_URL                             — E.g. https://<account>.r2.cloudflarestorage.com
    S3_BUCKET                                   — Bucket name

Bucket layout:
    images/<template>/<version>               # main disk
    images/<template>/<version>-N             # additional disks (e.g. storage pool members)
    images/<template>/latest                  # Text file containing the version string
    assets/<path>                               # Pre-fetched build inputs (e.g. Windows ISOs)

For pinned templates the version is the template content hash.
For rolling templates the version is the build date stamp (YYYYMMDD).
"""

import argparse
import hashlib
import os
import re
import sys
import urllib.request
from pathlib import Path
from typing import Any

import boto3
from botocore.exceptions import ClientError
from ruamel.yaml import YAML

REPO_ROOT = Path(__file__).resolve().parent.parent
TEMPLATES_ROOT = REPO_ROOT / "templates"
BUILD_ROOT = REPO_ROOT / "local" / "build"
ASSETS_ROOT = REPO_ROOT / "local"

# Retention defaults. Tweak via `--keep N` if needed.
DEFAULT_KEEP = 3


def _client() -> Any:
    return boto3.client("s3", endpoint_url=os.environ["S3_ENDPOINT_URL"], region_name="auto")


def _local_dir(template: str) -> Path:
    return BUILD_ROOT / template


def _find_local_disk(template: str) -> Path | None:
    candidate = _local_dir(template) / "disk"
    return candidate if candidate.exists() else None


def _is_disk_key(key: str) -> bool:
    return not key.endswith("/latest")


def _version_from_key(key: str) -> str:
    name = key.rsplit("/", 1)[-1]
    # Strip the -N suffix used for additional disks so they group with the main disk.
    return re.sub(r"-\d+$", "", name)


def _find_local_extras(template: str) -> list[tuple[int, Path]]:
    """Return (n, path) for each disk-N file found alongside the main disk."""
    base = _local_dir(template)
    result, n = [], 1
    while (p := base / f"disk-{n}").exists():
        result.append((n, p))
        n += 1
    return result


def upload(template: str, version: str) -> None:
    bucket = os.environ["S3_BUCKET"]

    local = _find_local_disk(template)
    if local is None:
        raise SystemExit(f"local image not found under {_local_dir(template)}")

    key = f"images/{template}/{version}"
    pointer = f"images/{template}/latest"
    s3 = _client()
    print(f"uploading {local} -> s3://{bucket}/{key}", file=sys.stderr)
    s3.upload_file(str(local), bucket, key)
    for n, extra in _find_local_extras(template):
        extra_key = f"images/{template}/{version}-{n}"
        print(f"uploading {extra} -> s3://{bucket}/{extra_key}", file=sys.stderr)
        s3.upload_file(str(extra), bucket, extra_key)
    print(f"updating pointer s3://{bucket}/{pointer} -> {version}", file=sys.stderr)
    s3.put_object(Bucket=bucket, Key=pointer, Body=version.encode(), ContentType="text/plain")


def download(template: str) -> None:
    bucket = os.environ["S3_BUCKET"]

    s3 = _client()
    pointer = f"images/{template}/latest"
    print(f"reading pointer s3://{bucket}/{pointer}", file=sys.stderr)
    version = s3.get_object(Bucket=bucket, Key=pointer)["Body"].read().decode().strip()

    local_dir = _local_dir(template)
    local_dir.mkdir(parents=True, exist_ok=True)
    # Download the main disk and any additional disks (disk-1, disk-2, …).
    prefix = f"images/{template}/{version}"
    keys = sorted(
        o["Key"] for o in s3.list_objects_v2(Bucket=bucket, Prefix=prefix).get("Contents", []) if _is_disk_key(o["Key"])
    )
    if not keys:
        raise SystemExit(f"no image found at s3://{bucket}/{prefix}")
    for obj_key in keys:
        name = obj_key.rsplit("/", 1)[-1]
        suffix = name[len(version) :]  # "" for main disk, "-1" for first extra, etc.
        local = local_dir / f"disk{suffix}"
        print(f"downloading s3://{bucket}/{obj_key} -> {local}", file=sys.stderr)
        s3.download_file(bucket, obj_key, str(local))
    print(version)


def exists(template: str, version: str) -> bool:
    bucket = os.environ["S3_BUCKET"]

    s3 = _client()
    key = f"images/{template}/{version}"
    listing = s3.list_objects_v2(Bucket=bucket, Prefix=key, MaxKeys=1).get("Contents", [])
    return bool(listing)


def prune(template: str, keep: int = DEFAULT_KEEP, dry: bool = False) -> None:
    bucket = os.environ["S3_BUCKET"]

    s3 = _client()
    prefix = f"images/{template}/"
    # Fetch every object under the template prefix; filter to known disk extensions.
    objects = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        objects.extend(obj for obj in page.get("Contents", []) if _is_disk_key(obj["Key"]))

    if not objects:
        print(f"{template}: no images in s3://{bucket}/{prefix}", file=sys.stderr)
        return

    # Always preserve the version the `latest` pointer references.
    current = None
    try:
        current = s3.get_object(Bucket=bucket, Key=f"{prefix}latest")["Body"].read().decode().strip()
    except ClientError as e:
        if e.response.get("Error", {}).get("Code") not in ("NoSuchKey", "404"):
            raise

    objects.sort(key=lambda o: o["LastModified"], reverse=True)
    keepers = {o["Key"] for o in objects[:keep]}
    if current is not None:
        for obj in objects:
            if _version_from_key(obj["Key"]) == current:
                keepers.add(obj["Key"])

    victims = [o for o in objects if o["Key"] not in keepers]
    if not victims:
        print(f"{template}: nothing to prune ({len(objects)} objects, keeping {len(keepers)})", file=sys.stderr)
        return

    verb = "would delete" if dry else "deleting"
    for obj in victims:
        print(f"{verb} s3://{bucket}/{obj['Key']}", file=sys.stderr)

    if dry:
        return

    s3.delete_objects(Bucket=bucket, Delete={"Objects": [{"Key": o["Key"]} for o in victims]})


def fetch_assets(template: str) -> None:
    """Fetch every asset declared under the template's image.yml ``assets:``.

    Entries are either a bare path (fetched from the S3 ``assets/`` prefix) or a
    mapping with ``path`` plus ``url`` (upstream HTTP source) and optional
    ``sha256`` to verify the downloaded bytes.
    """
    sidecar = TEMPLATES_ROOT / template / "image.yml"
    if not sidecar.is_file():
        raise SystemExit(f"no image.yml for template {template!r}")

    meta = YAML(typ="safe").load(sidecar)
    assets = meta.get("assets", [])
    if not assets:
        print(f"no assets declared for {template}", file=sys.stderr)
        return

    s3 = None
    bucket = None
    for entry in assets:
        if isinstance(entry, str):
            path, url, sha256 = entry, None, None
        else:
            path = entry["path"]
            url = entry.get("url")
            sha256 = entry.get("sha256")

        local = ASSETS_ROOT / path
        if local.exists():
            if sha256 is None:
                print(f"asset already present: {local}", file=sys.stderr)
                continue
            actual = _sha256_file(local)
            if actual == sha256.lower():
                print(f"asset already present (sha256 ok): {local}", file=sys.stderr)
                continue
            print(
                f"asset sha256 mismatch, re-downloading {local}: got {actual}, want {sha256.lower()}",
                file=sys.stderr,
            )
            local.unlink()

        local.parent.mkdir(parents=True, exist_ok=True)
        if url:
            _fetch_url(url, local, sha256)
        else:
            if s3 is None:
                bucket = os.environ["S3_BUCKET"]
                s3 = _client()
            key = f"assets/{path}"
            print(f"fetching s3://{bucket}/{key} -> {local}", file=sys.stderr)
            s3.download_file(bucket, key, str(local))


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


def _fetch_url(url: str, dest: Path, sha256: str | None) -> None:
    tmp = dest.with_suffix(dest.suffix + ".part")
    print(f"downloading {url} -> {dest}", file=sys.stderr)
    h = hashlib.sha256() if sha256 else None

    with urllib.request.urlopen(url) as resp, tmp.open("wb") as f:
        while chunk := resp.read(1 << 20):
            if h is not None:
                h.update(chunk)
            f.write(chunk)

    if h is not None:
        actual = h.hexdigest()
        if actual != sha256.lower():
            tmp.unlink()
            raise SystemExit(f"sha256 mismatch for {url}: got {actual}, want {sha256}")
    tmp.rename(dest)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="cmd", required=True)

    up = sub.add_parser("upload", help="upload a built image and update the latest pointer")
    up.add_argument("template", help="e.g. pinned/debian-12")
    up.add_argument("version", help="content hash (pinned) or date stamp (rolling)")

    down = sub.add_parser("download", help="download the latest known-good image for a template")
    down.add_argument("template")

    ex = sub.add_parser("exists", help="exit 0 if the image is already in the bucket, 1 if not")
    ex.add_argument("template")
    ex.add_argument("version")

    pr = sub.add_parser("prune", help="delete old image versions, keeping the newest N (+ latest pointer)")
    pr.add_argument("template")
    pr.add_argument("--keep", type=int, default=DEFAULT_KEEP, help="how many recent versions to retain")
    pr.add_argument("--dry", action="store_true", help="print what would be deleted without doing it")

    assets = sub.add_parser("fetch-assets", help="fetch assets declared in a template's image.yml")
    assets.add_argument("template")

    args = parser.parse_args()
    if args.cmd == "upload":
        upload(args.template, args.version)
    elif args.cmd == "download":
        download(args.template)
    elif args.cmd == "exists":
        sys.exit(0 if exists(args.template, args.version) else 1)
    elif args.cmd == "prune":
        prune(args.template, args.keep, args.dry)
    elif args.cmd == "fetch-assets":
        fetch_assets(args.template)


if __name__ == "__main__":
    main()
