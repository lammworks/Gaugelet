#!/bin/zsh

set -euo pipefail

fail() {
    print -u2 -- "error: $*"
    exit 1
}

if [[ -n "${GAUGELET_DEVELOPER_DIR:-}" ]]; then
    [[ -d "${GAUGELET_DEVELOPER_DIR}" ]] \
        || fail "GAUGELET_DEVELOPER_DIR is not a directory: ${GAUGELET_DEVELOPER_DIR}"
    print -- "${GAUGELET_DEVELOPER_DIR:A}"
    exit 0
fi

SELECTED="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
if [[ -n "${SELECTED}" && -x "${SELECTED}/usr/bin/xcodebuild" ]]; then
    print -- "${SELECTED:A}"
    exit 0
fi

if [[ -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]]; then
    print -- /Applications/Xcode.app/Contents/Developer
    exit 0
fi

FULL_XCODE="$(/usr/bin/find /Applications -maxdepth 3 \
    -path '*/Xcode*.app/Contents/Developer' \
    -type d -print 2>/dev/null \
    | /usr/bin/sort \
    | /usr/bin/awk 'NR == 1 { print }')"
if [[ -n "${FULL_XCODE}" && -x "${FULL_XCODE}/usr/bin/xcodebuild" ]]; then
    print -- "${FULL_XCODE:A}"
    exit 0
fi

[[ -n "${SELECTED}" && -d "${SELECTED}" ]] \
    || fail "no Apple developer tools directory is selected"
print -- "${SELECTED:A}"
