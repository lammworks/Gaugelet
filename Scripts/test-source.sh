#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
TEST_ROOT="${GAUGELET_TEST_ROOT:-${GAUGELET_SWIFTPM_BUILD_ROOT:-${ROOT_DIR}/.build}}"
SELECTED_DEVELOPER_DIR="$("${SCRIPT_DIR}/select-developer-dir.sh")"
SWIFT="${GAUGELET_SWIFT:-$(DEVELOPER_DIR="${SELECTED_DEVELOPER_DIR}" /usr/bin/xcrun --find swift 2>/dev/null || true)}"
HOST_ARCHITECTURE="$(/usr/bin/uname -m)"

fail() {
    print -u2 -- "error: $*"
    exit 1
}

[[ -x "${SWIFT}" ]] || fail "SwiftPM is unavailable"
[[ -f "${ROOT_DIR}/Package.resolved" ]] || fail "Package.resolved is required"
"${SCRIPT_DIR}/verify-sparkle-pin.py"
/usr/bin/install -d "${TEST_ROOT}"
TEST_ROOT="${TEST_ROOT:A}"
[[ "${TEST_ROOT}" != "/" && "${TEST_ROOT}" != "${ROOT_DIR}" ]] \
    || fail "refusing unsafe test scratch path: ${TEST_ROOT}"

MODULE_CACHE_ROOT="${TEST_ROOT}/ModuleCache"
SWIFTPM_CACHE_ROOT="${TEST_ROOT}/Cache"
TEST_FRAMEWORK_PATH="${TEST_ROOT}/out/Products/Debug"
if [[ -n "${DYLD_FRAMEWORK_PATH:-}" ]]; then
    TEST_FRAMEWORK_PATH="${TEST_FRAMEWORK_PATH}:${DYLD_FRAMEWORK_PATH}"
fi
/usr/bin/install -d "${MODULE_CACHE_ROOT}" "${SWIFTPM_CACHE_ROOT}"

DEVELOPER_DIR="${SELECTED_DEVELOPER_DIR}" \
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_ROOT}" \
SWIFT_MODULE_CACHE_PATH="${MODULE_CACHE_ROOT}" \
SWIFTPM_MODULECACHE_OVERRIDE="${MODULE_CACHE_ROOT}" \
XDG_CACHE_HOME="${SWIFTPM_CACHE_ROOT}" \
DYLD_FRAMEWORK_PATH="${TEST_FRAMEWORK_PATH}" \
"${SWIFT}" test \
    --package-path "${ROOT_DIR}" \
    --scratch-path "${TEST_ROOT}" \
    --configuration debug \
    --arch "${HOST_ARCHITECTURE}" \
    --disable-automatic-resolution \
    --disable-sandbox \
    --parallel

print -- "Gaugelet SwiftPM tests passed on ${HOST_ARCHITECTURE}"
