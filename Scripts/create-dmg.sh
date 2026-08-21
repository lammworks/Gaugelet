#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
APP_SOURCE="${1:-${ROOT_DIR}/build/Gaugelet.app}"
OUTPUT_DMG="${2:-}"
DMG_SETTINGS="${ROOT_DIR}/Packaging/dmg_settings.py"
DMG_BACKGROUND="${ROOT_DIR}/Packaging/DMG/background.png"
DMG_BACKGROUND_2X="${ROOT_DIR}/Packaging/DMG/background@2x.png"
DMG_PYTHON="${GAUGELET_DMGBUILD_PYTHON:-${ROOT_DIR}/.build/dmg-tools/bin/python}"

fail() {
    print -u2 -- "error: $*"
    exit 1
}

[[ -d "${APP_SOURCE}" ]] || fail "app bundle not found: ${APP_SOURCE}"
[[ -f "${DMG_SETTINGS}" ]] || fail "DMG settings not found: ${DMG_SETTINGS}"
[[ -f "${DMG_BACKGROUND}" && -f "${DMG_BACKGROUND_2X}" ]] \
    || fail "DMG background assets are missing"
[[ -x "${DMG_PYTHON}" ]] \
    || fail "pinned DMG tools are not installed; run Scripts/bootstrap-dmg-tools.sh"
"${DMG_PYTHON}" -c 'import dmgbuild, ds_store, mac_alias' \
    || fail "the configured DMG Python environment is incomplete"
INFO_PLIST="${APP_SOURCE}/Contents/Info.plist"
EXECUTABLE="${APP_SOURCE}/Contents/MacOS/Gaugelet"
[[ -f "${INFO_PLIST}" ]] || fail "app bundle has no Info.plist"
[[ -x "${EXECUTABLE}" ]] || fail "app bundle has no Gaugelet executable"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
if [[ -z "${OUTPUT_DMG}" ]]; then
    OUTPUT_DMG="${ROOT_DIR}/build/Gaugelet-${VERSION}.dmg"
fi
[[ "${OUTPUT_DMG:e}" == "dmg" ]] || fail "output must use the .dmg extension: ${OUTPUT_DMG}"

[[ "$(/usr/bin/lipo -archs "${EXECUTABLE}")" == "arm64" ]] \
    || fail "Gaugelet main executable must contain only arm64"
[[ -d "${APP_SOURCE}/Contents/Frameworks/Sparkle.framework" ]] \
    || fail "app bundle is missing Sparkle.framework"
GAUGELET_VERIFY_SPARKLE_SIGNATURES=1 \
    "${SCRIPT_DIR}/verify-sparkle-framework.sh" \
    "${APP_SOURCE}/Contents/Frameworks/Sparkle.framework"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_SOURCE}"

OUTPUT_DIR="${OUTPUT_DMG:h}"
/usr/bin/install -d "${OUTPUT_DIR}"
OUTPUT_DIR="${OUTPUT_DIR:A}"
OUTPUT_DMG="${OUTPUT_DIR}/${OUTPUT_DMG:t}"
[[ "${OUTPUT_DIR}" != "/" ]] || fail "refusing to write a disk image at the filesystem root"

LOCK_DIR="${OUTPUT_DIR}/.${OUTPUT_DMG:t}.lock"
LOCK_HELD=0
WORK_ROOT=""
MOUNT_ROOT=""
ATTACHED=0

if ! /bin/mkdir "${LOCK_DIR}" 2>/dev/null; then
    fail "another create-dmg process is writing ${OUTPUT_DMG}"
fi
LOCK_HELD=1
print -- "$$" > "${LOCK_DIR}/pid"

WORK_ROOT="$(/usr/bin/mktemp -d "${OUTPUT_DIR}/.create-dmg.XXXXXX")"
TEMP_DMG="${OUTPUT_DIR}/.${OUTPUT_DMG:t:r}.partial.$$.dmg"
MOUNT_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gaugelet-dmg-mount.XXXXXX")"

cleanup() {
    if (( ATTACHED )); then
        /usr/bin/hdiutil detach "${MOUNT_ROOT}" -quiet >/dev/null 2>&1 || true
    fi
    [[ -n "${MOUNT_ROOT}" && -d "${MOUNT_ROOT}" ]] && /bin/rmdir "${MOUNT_ROOT}" 2>/dev/null || true
    [[ -n "${WORK_ROOT}" && -d "${WORK_ROOT}" ]] && /bin/rm -rf "${WORK_ROOT}"
    [[ -n "${TEMP_DMG}" && -f "${TEMP_DMG}" ]] && /bin/rm -f "${TEMP_DMG}"
    if (( LOCK_HELD )) && [[ -d "${LOCK_DIR}" ]]; then
        /bin/rm -rf "${LOCK_DIR}"
    fi
}
trap cleanup EXIT INT TERM

BACKGROUND_WIDTH="$(/usr/bin/sips -g pixelWidth "${DMG_BACKGROUND}" 2>/dev/null \
    | /usr/bin/awk '/pixelWidth:/ { print $2 }')"
BACKGROUND_HEIGHT="$(/usr/bin/sips -g pixelHeight "${DMG_BACKGROUND}" 2>/dev/null \
    | /usr/bin/awk '/pixelHeight:/ { print $2 }')"
BACKGROUND_2X_WIDTH="$(/usr/bin/sips -g pixelWidth "${DMG_BACKGROUND_2X}" 2>/dev/null \
    | /usr/bin/awk '/pixelWidth:/ { print $2 }')"
BACKGROUND_2X_HEIGHT="$(/usr/bin/sips -g pixelHeight "${DMG_BACKGROUND_2X}" 2>/dev/null \
    | /usr/bin/awk '/pixelHeight:/ { print $2 }')"
[[ "${BACKGROUND_WIDTH}x${BACKGROUND_HEIGHT}" == "720x440" ]] \
    || fail "DMG background must be 720x440"
[[ "${BACKGROUND_2X_WIDTH}x${BACKGROUND_2X_HEIGHT}" == "1440x880" ]] \
    || fail "DMG @2x background must be 1440x880"

"${DMG_PYTHON}" -m dmgbuild \
    -s "${DMG_SETTINGS}" \
    -D "app=${APP_SOURCE:A}" \
    -D "background=${DMG_BACKGROUND:A}" \
    "Gaugelet" \
    "${TEMP_DMG}"

/usr/bin/hdiutil verify "${TEMP_DMG}" >/dev/null
/usr/bin/hdiutil imageinfo "${TEMP_DMG}" | /usr/bin/grep -E 'Format:[[:space:]]+UDZO' >/dev/null \
    || fail "disk image is not UDZO compressed/read-only"

/usr/bin/hdiutil attach \
    -readonly \
    -nobrowse \
    -mountpoint "${MOUNT_ROOT}" \
    "${TEMP_DMG}" >/dev/null
ATTACHED=1

[[ -d "${MOUNT_ROOT}/Gaugelet.app" && ! -L "${MOUNT_ROOT}/Gaugelet.app" ]] \
    || fail "disk image does not contain Gaugelet.app"
[[ -L "${MOUNT_ROOT}/Applications" ]] || fail "disk image does not contain the Applications symlink"
[[ "$(/usr/bin/readlink "${MOUNT_ROOT}/Applications")" == "/Applications" ]] \
    || fail "Applications symlink has the wrong target"
[[ -f "${MOUNT_ROOT}/.DS_Store" ]] || fail "disk image does not contain Finder layout metadata"
[[ -f "${MOUNT_ROOT}/.background.tiff" ]] || fail "disk image does not contain the styled background"
"${DMG_PYTHON}" "${SCRIPT_DIR}/verify-dmg-layout.py" "${MOUNT_ROOT}"
[[ "$(/usr/bin/lipo -archs "${MOUNT_ROOT}/Gaugelet.app/Contents/MacOS/Gaugelet")" == "arm64" ]] \
    || fail "mounted Gaugelet main executable must contain only arm64"
GAUGELET_VERIFY_SPARKLE_SIGNATURES=1 \
    "${SCRIPT_DIR}/verify-sparkle-framework.sh" \
    "${MOUNT_ROOT}/Gaugelet.app/Contents/Frameworks/Sparkle.framework"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${MOUNT_ROOT}/Gaugelet.app"

/usr/bin/hdiutil detach "${MOUNT_ROOT}" -quiet
ATTACHED=0
/bin/rmdir "${MOUNT_ROOT}"
MOUNT_ROOT=""

/bin/mv -f "${TEMP_DMG}" "${OUTPUT_DMG}"
TEMP_DMG=""

print -- "Created ${OUTPUT_DMG}"
print -- "Version ${VERSION} (${BUILD})"
print -- "Format UDZO (compressed, read-only, styled Finder layout)"
