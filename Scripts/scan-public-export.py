#!/usr/bin/env python3

from __future__ import annotations

import argparse
import base64
import binascii
import pathlib
import re
import sys


SECRET_PATTERNS = {
    "private key header": re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    "GitHub token": re.compile(rb"\bgh[pousr]_[A-Za-z0-9]{20,}\b"),
    "AWS access key": re.compile(rb"\bAKIA[0-9A-Z]{16}\b"),
    "Slack token": re.compile(rb"\bxox[baprs]-[A-Za-z0-9-]{20,}\b"),
    "Apple API private key": re.compile(rb"\bAuthKey_[A-Z0-9]{10}\.p8\b"),
    "high-risk assignment": re.compile(
        rb"(?i)\b(?:password|private[_-]?key|api[_-]?key|secret|token)\s*[:=]\s*['\"]?[A-Za-z0-9+/=_-]{16,}"
    ),
}
PII_PATTERNS = {
    # Assemble the signature so this scanner can scan its own source without
    # matching the generic pattern definition itself.
    "local home path": re.compile(rb"/" + rb"Users/[^/\s'\"]+"),
}
EMAIL_PATTERN = re.compile(rb"(?i)\b[A-Z0-9._%+-]+@[A-Z][A-Z0-9.-]*\.[A-Z]{2,}\b")
ALLOWED_EMAIL_DOMAINS = {"lammworks.com", "users.noreply.github.com"}
TEXT_SUFFIXES = {
    ".c", ".css", ".html", ".in", ".js", ".json", ".jsx", ".lock", ".m",
    ".md", ".mjs", ".plist", ".py", ".sh", ".swift", ".toml", ".ts", ".tsx",
    ".txt", ".xml", ".yaml", ".yml",
}
AGE_HEADERS = (
    b"age-encryption.org/v1",
    b"-----BEGIN AGE ENCRYPTED FILE-----",
)


def is_standalone_ed25519_key_material(data: bytes) -> bool:
    """Detect Sparkle's raw 32-byte seed or legacy 96-byte key export.

    The scanner intentionally reports only the file path and finding label. It
    never emits the candidate material.
    """
    candidate = data.strip()
    if len(candidate) not in {44, 128} or b"\n" in candidate or b"\r" in candidate:
        return False
    try:
        decoded = base64.b64decode(candidate, validate=True)
    except (binascii.Error, ValueError):
        return False
    return len(decoded) in {32, 96}


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


parser = argparse.ArgumentParser(description="Built-in secret and PII scan for Gaugelet public export")
parser.add_argument("root", type=pathlib.Path)
args = parser.parse_args()
root = args.root.resolve()
if not root.is_dir():
    fail(f"public export root is not a directory: {root}")
if root == pathlib.Path(root.anchor):
    fail("refusing to scan a filesystem root")
findings = []

for path in sorted(root.rglob("*")):
    if not path.is_file() or ".git" in path.relative_to(root).parts:
        continue
    if path.name == "PUBLIC_SOURCE_MANIFEST.sha256":
        continue
    data = path.read_bytes()
    relative = path.relative_to(root).as_posix()
    if path.suffix.lower() == ".age" or any(data.startswith(header) for header in AGE_HEADERS):
        findings.append(f"{relative}: encrypted recovery material must not be committed")
    if is_standalone_ed25519_key_material(data):
        findings.append(f"{relative}: standalone Ed25519 key material")
    for label, pattern in {**SECRET_PATTERNS, **PII_PATTERNS}.items():
        if pattern.search(data):
            findings.append(f"{relative}: {label}")
    if path.suffix.lower() in TEXT_SUFFIXES or b"\x00" not in data[:4096]:
        for match in EMAIL_PATTERN.finditer(data):
            email = match.group().decode("ascii", errors="ignore")
            domain = email.rsplit("@", 1)[-1].lower()
            if domain not in ALLOWED_EMAIL_DOMAINS:
                findings.append(f"{relative}: unapproved email domain in {email}")

if findings:
    for finding in sorted(set(findings)):
        print(f"error: {finding}", file=sys.stderr)
    fail("built-in public export secret/PII scan failed")

print("Built-in public export secret/PII scan passed")
