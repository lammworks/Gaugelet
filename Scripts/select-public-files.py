#!/usr/bin/env python3

from __future__ import annotations

import argparse
import fnmatch
import pathlib
import subprocess
import sys


FORBIDDEN_PREFIXES = (
    ".git/",
    ".build/",
    "build/",
    "DerivedData/",
    "QA/",
    "website/app/_sites-preview/",
    "website/examples/",
    "website/node_modules/",
    "website/.next/",
)
FORBIDDEN_FILES = {
    "APP_STORE_FEASIBILITY.md",
    "MONETIZATION.md",
    "RELEASE_READINESS.md",
    "design-qa.md",
    "Assets/IMAGEGEN_PROMPTS.md",
    "Assets/IconVariants/GaugeletIcon-Legacy-1024.png",
}
FORBIDDEN_COMPONENTS = {
    "Dipstick",
    "dipstick",
    "__pycache__",
}
FORBIDDEN_MEDIA_MARKERS = ("raw", "unsanitized", "private", "reference")
MEDIA_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".tiff"}


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


parser = argparse.ArgumentParser(description="Select Gaugelet's allowlisted public snapshot")
parser.add_argument("--root", required=True, type=pathlib.Path)
parser.add_argument("--allowlist", required=True, type=pathlib.Path)
parser.add_argument("--nul", action="store_true")
args = parser.parse_args()

root = args.root.resolve()
patterns = []
for raw_line in args.allowlist.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if line and not line.startswith("#"):
        patterns.append(line)
if not patterns:
    fail("public export allowlist is empty")

result = subprocess.run(
    ["git", "-C", str(root), "ls-files", "-z"],
    check=True,
    capture_output=True,
)
tracked = [item.decode("utf-8") for item in result.stdout.split(b"\0") if item]
selected = []
for relative in sorted(tracked):
    if relative in FORBIDDEN_FILES:
        continue
    if relative.startswith(FORBIDDEN_PREFIXES):
        continue
    if any(component in FORBIDDEN_COMPONENTS for component in pathlib.PurePosixPath(relative).parts):
        continue
    if not any(fnmatch.fnmatchcase(relative, pattern) for pattern in patterns):
        continue
    suffix = pathlib.PurePosixPath(relative).suffix.lower()
    if relative.startswith("website/") and suffix in MEDIA_SUFFIXES:
        lowered_parts = {part.lower() for part in pathlib.PurePosixPath(relative).parts}
        if lowered_parts.intersection(FORBIDDEN_MEDIA_MARKERS):
            continue
        if relative not in patterns:
            fail(
                "website raster media requires an exact, visually reviewed "
                f"public-export allowlist entry: {relative}"
            )
    selected.append(relative)

required = {"LICENSE", "README.md", "Package.swift", "Package.resolved"}
missing = sorted(required.difference(selected))
if missing:
    fail(f"public allowlist omitted required files: {', '.join(missing)}")

separator = "\0" if args.nul else "\n"
sys.stdout.write(separator.join(selected))
if selected:
    sys.stdout.write(separator)
