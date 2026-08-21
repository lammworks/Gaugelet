#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import pathlib
import sys


MANIFEST_NAME = "PUBLIC_SOURCE_MANIFEST.sha256"


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def digest(path: pathlib.Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def files(root: pathlib.Path) -> list[pathlib.Path]:
    output = []
    for path in root.rglob("*"):
        if ".git" in path.relative_to(root).parts:
            continue
        if path.name == MANIFEST_NAME:
            continue
        if path.is_symlink():
            fail(f"public snapshot must not contain symlinks: {path.relative_to(root)}")
        if path.is_file():
            output.append(path)
    return sorted(output, key=lambda item: item.relative_to(root).as_posix())


parser = argparse.ArgumentParser(description="Create or verify Gaugelet public snapshot hashes")
parser.add_argument("root", type=pathlib.Path)
parser.add_argument("--verify", action="store_true")
args = parser.parse_args()
root = args.root.resolve()
if not root.is_dir():
    fail(f"snapshot root is not a directory: {root}")
if root == pathlib.Path(root.anchor):
    fail("refusing to create or verify a manifest at a filesystem root")
manifest = root / MANIFEST_NAME

if args.verify:
    if not manifest.is_file():
        fail(f"missing {MANIFEST_NAME}")
    expected = {}
    for line in manifest.read_text(encoding="utf-8").splitlines():
        if not line:
            continue
        checksum, separator, relative = line.partition("  ")
        if not separator or len(checksum) != 64:
            fail(f"malformed manifest line: {line!r}")
        expected[relative] = checksum
    actual_paths = files(root)
    actual_names = {path.relative_to(root).as_posix() for path in actual_paths}
    if actual_names != set(expected):
        missing = sorted(set(expected).difference(actual_names))
        extra = sorted(actual_names.difference(expected))
        fail(f"manifest file set differs; missing={missing}, extra={extra}")
    for path in actual_paths:
        relative = path.relative_to(root).as_posix()
        if digest(path) != expected[relative]:
            fail(f"hash mismatch: {relative}")
    print(f"Public source manifest verified: {len(actual_paths)} files")
else:
    entries = [
        f"{digest(path)}  {path.relative_to(root).as_posix()}"
        for path in files(root)
    ]
    manifest.write_text("\n".join(entries) + "\n", encoding="utf-8")
    print(f"Public source manifest created: {len(entries)} files")
