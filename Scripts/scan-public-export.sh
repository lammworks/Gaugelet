#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
SCAN_ROOT="${1:-}"

fail() {
    print -u2 -- "error: $*"
    exit 1
}

[[ -n "${SCAN_ROOT}" && -d "${SCAN_ROOT}" ]] \
    || fail "usage: scan-public-export.sh /path/to/public-snapshot"
SCAN_ROOT="${SCAN_ROOT:A}"
[[ "${SCAN_ROOT}" != "/" && "${SCAN_ROOT}" != "${ROOT_DIR}" ]] \
    || fail "refusing unsafe scan root: ${SCAN_ROOT}"

"${SCRIPT_DIR}/scan-public-export.py" "${SCAN_ROOT}"

if command -v gitleaks >/dev/null 2>&1; then
    gitleaks detect --no-git --redact --source "${SCAN_ROOT}" --exit-code 1
    print -- "gitleaks scan passed"
elif [[ "${GAUGELET_REQUIRE_EXTERNAL_SCANNERS:-0}" == "1" ]]; then
    fail "gitleaks is required for this public export gate but is not installed"
else
    print -u2 -- "warning: gitleaks is unavailable; built-in fail-closed patterns ran, but final public export still requires GitHub secret scanning/push protection"
fi

if command -v detect-secrets >/dev/null 2>&1; then
    DETECT_OUTPUT="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/gaugelet-detect-secrets.XXXXXX")"
    cleanup() {
        [[ -f "${DETECT_OUTPUT}" ]] && /bin/rm -f "${DETECT_OUTPUT}"
    }
    trap cleanup EXIT INT TERM
    detect-secrets scan "${SCAN_ROOT}" > "${DETECT_OUTPUT}"
    /usr/bin/python3 - "${DETECT_OUTPUT}" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
results = data.get("results", {})
if any(results.values()):
    for path, findings in sorted(results.items()):
        if findings:
            print(f"error: detect-secrets finding in {path}", file=sys.stderr)
    raise SystemExit(1)
PY
    print -- "detect-secrets scan passed"
else
    print -u2 -- "warning: detect-secrets is unavailable; gitleaks and the built-in secret/PII scanner remain mandatory for public export"
fi
