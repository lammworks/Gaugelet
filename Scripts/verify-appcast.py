#!/usr/bin/env python3

from __future__ import annotations

import argparse
import base64
import binascii
import pathlib
import re
import sys
import xml.etree.ElementTree as ET


SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SIGNATURE_MARKER = b"<!-- sparkle-signatures:\n"


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


parser = argparse.ArgumentParser(description="Verify Gaugelet's signed Sparkle appcast")
parser.add_argument("appcast", type=pathlib.Path)
parser.add_argument("--version", required=True)
parser.add_argument("--build", required=True)
parser.add_argument("--url", required=True)
parser.add_argument("--archive", required=True, type=pathlib.Path)
parser.add_argument("--print-archive-signature", action="store_true")
args = parser.parse_args()

if not args.appcast.is_file():
    fail(f"appcast is missing: {args.appcast}")
data = args.appcast.read_bytes()
if not args.archive.is_file():
    fail(f"update archive is missing: {args.archive}")
marker_offset = data.rfind(SIGNATURE_MARKER)
if marker_offset < 0:
    fail("appcast has no Sparkle signed-feed block")

xml_data = data[:marker_offset]
signing_block = data[marker_offset:].decode("utf-8", errors="strict")
signing_match = re.fullmatch(
    r"<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/=]+)\nlength: (\d+)\n-->\n?",
    signing_block,
)
if signing_match is None:
    fail("appcast signed-feed block is malformed or has trailing content")
if int(signing_match.group(2)) != len(xml_data):
    fail("appcast signed-feed length does not match the signed XML bytes")

for label, signature in (("feed", signing_match.group(1)),):
    try:
        decoded = base64.b64decode(signature, validate=True)
    except (binascii.Error, ValueError) as error:
        fail(f"{label} signature is not valid base64: {error}")
    if len(decoded) != 64:
        fail(f"{label} signature decodes to {len(decoded)} bytes, expected 64")

try:
    root = ET.fromstring(xml_data)
except ET.ParseError as error:
    fail(f"appcast XML is invalid: {error}")

items = root.findall("./channel/item")
if len(items) != 1:
    fail(f"1.0 full-update appcast must contain exactly one item, found {len(items)}")
item = items[0]
version = item.findtext(f"{{{SPARKLE_NAMESPACE}}}shortVersionString")
build = item.findtext(f"{{{SPARKLE_NAMESPACE}}}version")
if version != args.version:
    fail(f"appcast short version is {version!r}, expected {args.version!r}")
if build != args.build:
    fail(f"appcast build is {build!r}, expected {args.build!r}")

enclosures = item.findall("enclosure")
if len(enclosures) != 1:
    fail(f"appcast item must contain one full enclosure, found {len(enclosures)}")
enclosure = enclosures[0]
if enclosure.get("url") != args.url:
    fail(f"enclosure URL is {enclosure.get('url')!r}, expected {args.url!r}")
archive_length = enclosure.get("length")
if archive_length is None or not archive_length.isdecimal():
    fail("full DMG enclosure has no valid length")
if int(archive_length) != args.archive.stat().st_size:
    fail(
        f"enclosure length is {archive_length}, "
        f"but {args.archive.name} is {args.archive.stat().st_size} bytes"
    )
if enclosure.get(f"{{{SPARKLE_NAMESPACE}}}deltaFrom") is not None:
    fail("delta updates are disabled for Gaugelet 1.0")
archive_signature = enclosure.get(f"{{{SPARKLE_NAMESPACE}}}edSignature")
if archive_signature is None:
    fail("full DMG enclosure has no EdDSA signature")
try:
    archive_decoded = base64.b64decode(archive_signature, validate=True)
except (binascii.Error, ValueError) as error:
    fail(f"archive signature is not valid base64: {error}")
if len(archive_decoded) != 64:
    fail(f"archive signature decodes to {len(archive_decoded)} bytes, expected 64")

if args.print_archive_signature:
    print(archive_signature)
else:
    print(
        f"Signed appcast verified: Gaugelet {args.version} ({args.build}), "
        "one version-specific full DMG, no deltas"
    )
