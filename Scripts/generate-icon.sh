#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
SOURCE_ICON="${GAUGELET_ICON_SOURCE:-${ROOT_DIR}/Assets/GaugeletIcon-1024.png}"
OUTPUT_ICON="${1:-${ROOT_DIR}/Packaging/Gaugelet.icns}"

fail() {
    print -u2 -- "error: $*"
    exit 1
}

[[ -f "${SOURCE_ICON}" ]] || fail "icon source not found: ${SOURCE_ICON}"
[[ "${OUTPUT_ICON:e}" == "icns" ]] || fail "output must use the .icns extension: ${OUTPUT_ICON}"

WIDTH="$(/usr/bin/sips -g pixelWidth "${SOURCE_ICON}" 2>/dev/null | /usr/bin/awk '/pixelWidth:/ { print $2 }')"
HEIGHT="$(/usr/bin/sips -g pixelHeight "${SOURCE_ICON}" 2>/dev/null | /usr/bin/awk '/pixelHeight:/ { print $2 }')"
[[ "${WIDTH}" == "1024" && "${HEIGHT}" == "1024" ]] || \
    fail "icon source must be exactly 1024x1024 pixels; found ${WIDTH:-unknown}x${HEIGHT:-unknown}"

OUTPUT_DIR="${OUTPUT_ICON:h}"
[[ -d "${OUTPUT_DIR}" ]] || /usr/bin/install -d "${OUTPUT_DIR}"

WORK_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gaugelet-icon.XXXXXX")"
TIFF_ROOT="${WORK_ROOT}/tiff"
COMBINED_TIFF="${WORK_ROOT}/Gaugelet.tiff"
TEMP_ICNS="${WORK_ROOT}/Gaugelet.icns"
VALIDATION_ICONSET="${WORK_ROOT}/Validation.iconset"

cleanup() {
    /bin/rm -rf "${WORK_ROOT}"
}
trap cleanup EXIT INT TERM

/usr/bin/install -d "${TIFF_ROOT}"

resize_icon() {
    local pixels="$1"
    local output="${TIFF_ROOT}/icon-${pixels}.tiff"
    /usr/bin/sips -z "${pixels}" "${pixels}" "${SOURCE_ICON}" \
        -s format tiff \
        --out "${output}" >/dev/null
}

resize_icon 16
resize_icon 32
resize_icon 48
resize_icon 128
resize_icon 256
resize_icon 512
resize_icon 1024

# iconutil rejects valid hand-authored iconsets on some Command Line Tools
# releases. Apple's tiff2icns accepts a multi-representation TIFF and emits a
# native ICNS container without relying on Xcode asset-catalog tooling.
/usr/bin/tiffutil -catnosizecheck \
    "${TIFF_ROOT}/icon-16.tiff" \
    "${TIFF_ROOT}/icon-32.tiff" \
    "${TIFF_ROOT}/icon-48.tiff" \
    "${TIFF_ROOT}/icon-128.tiff" \
    "${TIFF_ROOT}/icon-256.tiff" \
    "${TIFF_ROOT}/icon-512.tiff" \
    "${TIFF_ROOT}/icon-1024.tiff" \
    -out "${COMBINED_TIFF}" >/dev/null
/usr/bin/tiff2icns "${COMBINED_TIFF}" "${TEMP_ICNS}"
[[ -s "${TEMP_ICNS}" ]] || fail "tiff2icns did not produce an ICNS file"

/usr/bin/iconutil --convert iconset --output "${VALIDATION_ICONSET}" "${TEMP_ICNS}"
[[ -f "${VALIDATION_ICONSET}/icon_16x16.png" ]] || fail "ICNS validation is missing 16x16"
[[ -f "${VALIDATION_ICONSET}/icon_512x512.png" ]] || fail "ICNS validation is missing 512x512"

TEMP_OUTPUT="${OUTPUT_DIR}/.${OUTPUT_ICON:t}.tmp.$$"
/usr/bin/install -m 644 "${TEMP_ICNS}" "${TEMP_OUTPUT}"
/bin/mv -f "${TEMP_OUTPUT}" "${OUTPUT_ICON}"

print -- "Generated ${OUTPUT_ICON}"
