#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
TOOL_NAME="${1:-}"

fail() {
    print -u2 -- "error: $*"
    exit 1
}

case "${TOOL_NAME}" in
    generate_appcast|generate_keys|sign_update) ;;
    *) fail "usage: sparkle-tool-path.sh generate_appcast|generate_keys|sign_update" ;;
esac

if [[ -n "${GAUGELET_SPARKLE_TOOLS_DIR:-}" ]]; then
    configured="${GAUGELET_SPARKLE_TOOLS_DIR}/${TOOL_NAME}"
    [[ -x "${configured}" ]] || fail "Sparkle tool is not executable: ${configured}"
    print -- "${configured:A}"
    exit 0
fi

typeset -a CANDIDATES
CANDIDATES=()
while IFS= read -r candidate; do
    CANDIDATES+=("${candidate}")
done < <(/usr/bin/find "${ROOT_DIR}/.build/artifacts" \
    -type f -path "*/Sparkle/bin/${TOOL_NAME}" -perm -111 -print 2>/dev/null | /usr/bin/sort)

(( ${#CANDIDATES[@]} == 1 )) \
    || fail "expected one SwiftPM ${TOOL_NAME} tool, found ${#CANDIDATES[@]}; build Gaugelet first or set GAUGELET_SPARKLE_TOOLS_DIR"
print -- "${CANDIDATES[1]:A}"
