#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
UV_BIN="${GAUGELET_UV_BIN:-$(command -v uv || true)}"
TOOLS_ROOT="${GAUGELET_DMG_TOOLS_ROOT:-${ROOT_DIR}/.build/dmg-tools}"
LOCK_FILE="${ROOT_DIR}/Packaging/dmg-requirements.lock"
UV_CACHE_DIR="${GAUGELET_UV_CACHE_DIR:-${ROOT_DIR}/.build/uv-cache}"

fail() {
    print -u2 -- "error: $*"
    exit 1
}

[[ -n "${UV_BIN}" && -x "${UV_BIN}" ]] || fail "uv is required to install the pinned DMG tools"
[[ -f "${LOCK_FILE}" ]] || fail "missing ${LOCK_FILE}"
[[ "${TOOLS_ROOT}" == /* && "${TOOLS_ROOT:t}" == "dmg-tools" ]] \
    || fail "GAUGELET_DMG_TOOLS_ROOT must be an absolute, dedicated dmg-tools directory"
[[ "${UV_CACHE_DIR}" == /* && "${UV_CACHE_DIR:t}" == "uv-cache" ]] \
    || fail "GAUGELET_UV_CACHE_DIR must be an absolute, dedicated uv-cache directory"
[[ "${TOOLS_ROOT}" != "/" && "${TOOLS_ROOT}" != "${ROOT_DIR}" ]] \
    || fail "refusing unsafe DMG tools directory"
[[ "${UV_CACHE_DIR}" != "/" && "${UV_CACHE_DIR}" != "${ROOT_DIR}" ]] \
    || fail "refusing unsafe uv cache directory"

/usr/bin/install -d "${TOOLS_ROOT:h}" "${UV_CACHE_DIR}"
TOOLS_ROOT="${TOOLS_ROOT:A}"
UV_CACHE_DIR="${UV_CACHE_DIR:A}"
[[ "${TOOLS_ROOT}" != "/" && "${TOOLS_ROOT}" != "${ROOT_DIR}" ]] \
    || fail "DMG tools directory resolves to an unsafe path"
[[ "${UV_CACHE_DIR}" != "/" && "${UV_CACHE_DIR}" != "${ROOT_DIR}" ]] \
    || fail "uv cache directory resolves to an unsafe path"
if [[ ! -x "${TOOLS_ROOT}/bin/python" ]]; then
    UV_CACHE_DIR="${UV_CACHE_DIR}" "${UV_BIN}" venv "${TOOLS_ROOT}"
fi

UV_CACHE_DIR="${UV_CACHE_DIR}" "${UV_BIN}" pip sync \
    --python "${TOOLS_ROOT}/bin/python" \
    --require-hashes \
    "${LOCK_FILE}"

"${TOOLS_ROOT}/bin/python" -c 'import dmgbuild, ds_store, mac_alias'
print -- "DMG tools ready: ${TOOLS_ROOT}"
