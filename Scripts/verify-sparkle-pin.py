#!/usr/bin/env python3

from __future__ import annotations

import json
import pathlib
import re
import sys


EXPECTED_VERSION = "2.9.5"
EXPECTED_REVISION = "79bc9e872948e47877e76f194cb0c8e0412b0b90"
EXPECTED_LOCATION = "https://github.com/sparkle-project/Sparkle"


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


root = pathlib.Path(__file__).resolve().parent.parent
manifest = root / "Package.swift"
resolved = root / "Package.resolved"

if not manifest.is_file() or not resolved.is_file():
    fail("Package.swift and Package.resolved are required")

manifest_text = manifest.read_text(encoding="utf-8")
exact_pattern = re.compile(
    r"\.package\s*\(\s*url:\s*\"https://github\.com/sparkle-project/Sparkle\"\s*,"
    r"\s*exact:\s*\"2\.9\.5\"\s*\)",
    re.DOTALL,
)
if exact_pattern.search(manifest_text) is None:
    fail("Package.swift must pin Sparkle with exact: \"2.9.5\"")

try:
    resolved_data = json.loads(resolved.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as error:
    fail(f"could not parse Package.resolved: {error}")

pins = [pin for pin in resolved_data.get("pins", []) if pin.get("identity") == "sparkle"]
if len(pins) != 1:
    fail(f"Package.resolved must contain one Sparkle pin, found {len(pins)}")

pin = pins[0]
state = pin.get("state", {})
if pin.get("location") != EXPECTED_LOCATION:
    fail(f"Sparkle pin location is {pin.get('location')!r}, expected {EXPECTED_LOCATION!r}")
if state.get("version") != EXPECTED_VERSION:
    fail(f"Sparkle pin version is {state.get('version')!r}, expected {EXPECTED_VERSION!r}")
if state.get("revision") != EXPECTED_REVISION:
    fail(
        f"Sparkle 2.9.5 revision is {state.get('revision')!r}, "
        f"expected {EXPECTED_REVISION!r}"
    )

print(f"Sparkle pin verified: {EXPECTED_VERSION} ({EXPECTED_REVISION})")
