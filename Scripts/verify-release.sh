#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
REQUIRE_APPCAST=0
if [[ "${1:-}" == "--require-appcast" ]]; then
    REQUIRE_APPCAST=1
    shift
fi
RELEASE_ROOT="${1:-${ROOT_DIR}/build/release}"
MOUNT_ROOT=""
EXTRACT_ROOT=""
ATTACHED=0

fail() {
    print -u2 -- "error: $*"
    exit 1
}

cleanup() {
    if (( ATTACHED )); then
        /usr/bin/hdiutil detach "${MOUNT_ROOT}" -quiet >/dev/null 2>&1 || true
    fi
    [[ -n "${MOUNT_ROOT}" && -d "${MOUNT_ROOT}" ]] && /bin/rmdir "${MOUNT_ROOT}" 2>/dev/null || true
    [[ -n "${EXTRACT_ROOT}" && -d "${EXTRACT_ROOT}" ]] && /bin/rm -rf "${EXTRACT_ROOT}"
}
trap cleanup EXIT INT TERM

[[ -d "${RELEASE_ROOT}" ]] || fail "release directory not found: ${RELEASE_ROOT}"
RELEASE_ROOT="${RELEASE_ROOT:A}"
[[ "${RELEASE_ROOT}" != "/" && "${RELEASE_ROOT}" != "${ROOT_DIR}" ]] \
    || fail "refusing unsafe release directory: ${RELEASE_ROOT}"

for asset in Gaugelet.dmg Gaugelet.dmg.sha256 Gaugelet.app.dSYM.zip build-evidence.txt release-evidence.txt; do
    [[ -s "${RELEASE_ROOT}/${asset}" ]] || fail "missing release asset: ${asset}"
done
if (( REQUIRE_APPCAST )); then
    [[ -s "${RELEASE_ROOT}/appcast.xml" ]] || fail "signed appcast.xml is required"
    [[ -s "${RELEASE_ROOT}/sparkle-evidence.txt" ]] || fail "sparkle-evidence.txt is required"
fi

if /usr/bin/find "${RELEASE_ROOT}" -maxdepth 1 -type f \
    \( -name '*.delta' -o -name '*private*key*' -o -name '*.age' -o -name '*.p8' -o -name '*.pem' \) \
    -print | /usr/bin/grep -q .; then
    fail "release directory contains a delta or private-key-shaped file"
fi
if /usr/bin/find "${RELEASE_ROOT}" -maxdepth 1 -type f -name 'Gaugelet-*.dmg' -print \
    | /usr/bin/grep -q .; then
    fail "release DMG must use the stable asset name Gaugelet.dmg"
fi

(
    cd "${RELEASE_ROOT}"
    /usr/bin/shasum -a 256 -c Gaugelet.dmg.sha256
)
/usr/bin/hdiutil verify "${RELEASE_ROOT}/Gaugelet.dmg" >/dev/null
/usr/bin/hdiutil imageinfo "${RELEASE_ROOT}/Gaugelet.dmg" \
    | /usr/bin/grep -E 'Format:[[:space:]]+UDZO' >/dev/null \
    || fail "Gaugelet.dmg is not compressed/read-only UDZO"

MOUNT_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gaugelet-release-verify.XXXXXX")"
/usr/bin/hdiutil attach \
    -readonly \
    -nobrowse \
    -mountpoint "${MOUNT_ROOT}" \
    "${RELEASE_ROOT}/Gaugelet.dmg" >/dev/null
ATTACHED=1
APP_PATH="${MOUNT_ROOT}/Gaugelet.app"
[[ -d "${APP_PATH}" && ! -L "${APP_PATH}" ]] || fail "DMG does not contain Gaugelet.app"
[[ -L "${MOUNT_ROOT}/Applications" ]] || fail "DMG does not contain the Applications symlink"
[[ "$(/usr/bin/readlink "${MOUNT_ROOT}/Applications")" == "/Applications" ]] \
    || fail "Applications symlink target is incorrect"
[[ -f "${MOUNT_ROOT}/.DS_Store" && -f "${MOUNT_ROOT}/.background.tiff" ]] \
    || fail "DMG Finder presentation files are missing"

DMG_PYTHON="${GAUGELET_DMGBUILD_PYTHON:-${ROOT_DIR}/.build/dmg-tools/bin/python}"
[[ -x "${DMG_PYTHON}" ]] || fail "pinned DMG verifier is unavailable"
"${DMG_PYTHON}" "${SCRIPT_DIR}/verify-dmg-layout.py" "${MOUNT_ROOT}"

APP_INFO="${APP_PATH}/Contents/Info.plist"
EXECUTABLE="${APP_PATH}/Contents/MacOS/Gaugelet"
FRAMEWORK="${APP_PATH}/Contents/Frameworks/Sparkle.framework"
SOURCE_PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${ROOT_DIR}/Packaging/Info.plist" 2>/dev/null || true)"
PACKAGED_PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${APP_INFO}" 2>/dev/null || true)"
[[ -n "${SOURCE_PUBLIC_KEY}" && "${PACKAGED_PUBLIC_KEY}" == "${SOURCE_PUBLIC_KEY}" ]] \
    || fail "packaged SUPublicEDKey is missing or differs from the committed public key"
"${SCRIPT_DIR}/verify-sparkle-key-gates.sh" --configuration-only --plist "${APP_INFO}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_INFO}")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP_INFO}")"
[[ "${VERSION}" == "1.0.1" && "${BUILD}" == "2" ]] \
    || fail "release bundle is ${VERSION} (${BUILD}), expected 1.0.1 (2)"
[[ "$(/usr/bin/lipo -archs "${EXECUTABLE}")" == "arm64" ]] \
    || fail "Gaugelet main executable must contain only arm64"
RPATHS="$(/usr/bin/otool -l "${EXECUTABLE}" \
    | /usr/bin/awk '$1 == "cmd" && $2 == "LC_RPATH" { want = 1; next } want && $1 == "path" { print $2; want = 0 }')"
[[ "${RPATHS}" == '@executable_path/../Frameworks' ]] \
    || fail "Gaugelet must contain only the bundle-relative Sparkle rpath; found: ${RPATHS:-none}"
/usr/bin/otool -L "${EXECUTABLE}" | /usr/bin/grep -F '@rpath/Sparkle.framework/' >/dev/null \
    || fail "Gaugelet does not load Sparkle through @rpath"

GAUGELET_VERIFY_SPARKLE_SIGNATURES=1 \
    "${SCRIPT_DIR}/verify-sparkle-framework.sh" "${FRAMEWORK}"
/usr/bin/codesign --verify --deep --strict --verbose=4 "${APP_PATH}"
while IFS= read -r nested_bundle; do
    /usr/bin/codesign --verify --deep --strict --verbose=2 "${nested_bundle}"
done < <(/usr/bin/find "${FRAMEWORK}" -depth -type d \
    \( -name '*.app' -o -name '*.xpc' \) -print)

/usr/bin/codesign -d --verbose=4 "${APP_PATH}" > "${RELEASE_ROOT}/.signature-verification.tmp.$$" 2>&1
SIGNATURE_REPORT="${RELEASE_ROOT}/.signature-verification.tmp.$$"
if [[ "${GAUGELET_EXPECT_DEVELOPER_ID:-0}" == "1" ]]; then
    /usr/bin/grep -F 'Authority=Developer ID Application:' "${SIGNATURE_REPORT}" >/dev/null \
        || fail "expected Developer ID Application signing"
    /usr/bin/grep -F 'runtime' "${SIGNATURE_REPORT}" >/dev/null \
        || fail "Developer ID build is missing hardened runtime"
else
    /usr/bin/grep -F 'Signature=adhoc' "${SIGNATURE_REPORT}" >/dev/null \
        || fail "community app is not ad-hoc signed"
    if /usr/bin/grep -F 'runtime' "${SIGNATURE_REPORT}" >/dev/null; then
        fail "community app unexpectedly enables hardened runtime/library validation"
    fi
fi
/bin/rm -f "${SIGNATURE_REPORT}"

LEGACY_FINDER_ICON="${APP_PATH}/Icon"$'\r'
[[ ! -e "${LEGACY_FINDER_ICON}" ]] || fail "app contains a legacy custom Finder icon"
for extended_attribute in com.apple.FinderInfo com.apple.ResourceFork; do
    if /usr/bin/xattr -p "${extended_attribute}" "${APP_PATH}" >/dev/null 2>&1; then
        fail "app contains forbidden ${extended_attribute} metadata"
    fi
done
[[ -s "${APP_PATH}/Contents/Resources/AppIcon.icns" ]] || fail "compiled AppIcon.icns is missing"
PACKAGED_MENU_BAR_ICON="${APP_PATH}/Contents/Resources/GaugeletMenuBar.svg"
SOURCE_MENU_BAR_ICON="${ROOT_DIR}/Assets/GaugeletMenuBar.svg"
[[ -s "${PACKAGED_MENU_BAR_ICON}" ]] || fail "packaged menu-bar SVG is missing"
/usr/bin/cmp "${SOURCE_MENU_BAR_ICON}" "${PACKAGED_MENU_BAR_ICON}" \
    || fail "packaged menu-bar SVG differs from the committed source"
/usr/bin/xmllint --noout "${PACKAGED_MENU_BAR_ICON}"
ICON_RENDER="${RELEASE_ROOT}/.app-icon-verification.tmp.$$.png"
/usr/bin/sips -s format png "${APP_PATH}/Contents/Resources/AppIcon.icns" \
    --out "${ICON_RENDER}" >/dev/null
HAS_ALPHA="$(/usr/bin/sips -g hasAlpha "${ICON_RENDER}" 2>/dev/null \
    | /usr/bin/awk '/hasAlpha:/ { print $2 }')"
/bin/rm -f "${ICON_RENDER}"
[[ "${HAS_ALPHA}" == "yes" ]] || fail "compiled AppIcon.icns has no transparency"

if [[ "${GAUGELET_EXPECT_DEVELOPER_ID:-0}" != "1" ]]; then
    APP_GATEKEEPER_LOG="${RELEASE_ROOT}/.app-gatekeeper.tmp.$$"
    if /usr/sbin/spctl --assess --type execute --verbose=4 "${APP_PATH}" \
        > "${APP_GATEKEEPER_LOG}" 2>&1; then
        fail "Gatekeeper unexpectedly accepted the non-notarized ad-hoc community app"
    fi
    /bin/rm -f "${APP_GATEKEEPER_LOG}"
fi

/usr/bin/hdiutil detach "${MOUNT_ROOT}" -quiet
ATTACHED=0
/bin/rmdir "${MOUNT_ROOT}"
MOUNT_ROOT=""

EXTRACT_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gaugelet-dsym-verify.XXXXXX")"
/usr/bin/ditto -x -k "${RELEASE_ROOT}/Gaugelet.app.dSYM.zip" "${EXTRACT_ROOT}"
DSYM="${EXTRACT_ROOT}/Gaugelet.app.dSYM"
[[ -d "${DSYM}" ]] || fail "dSYM archive does not contain Gaugelet.app.dSYM"
/usr/bin/dwarfdump --uuid "${DSYM}" > "${EXTRACT_ROOT}/uuids.txt"
/usr/bin/grep -F '(arm64)' "${EXTRACT_ROOT}/uuids.txt" >/dev/null \
    || fail "dSYM archive is missing arm64"
if /usr/bin/grep -F '(x86_64)' "${EXTRACT_ROOT}/uuids.txt" >/dev/null; then
    fail "dSYM archive unexpectedly contains x86_64"
fi

if (( REQUIRE_APPCAST )); then
    EXPECTED_URL="https://github.com/lammworks/Gaugelet/releases/download/v${VERSION}/Gaugelet.dmg"
    "${SCRIPT_DIR}/verify-appcast.py" \
        "${RELEASE_ROOT}/appcast.xml" \
        --version "${VERSION}" \
        --build "${BUILD}" \
        --url "${EXPECTED_URL}" \
        --archive "${RELEASE_ROOT}/Gaugelet.dmg"
fi

print -- "Release artifact verified: Gaugelet ${VERSION} (${BUILD}), arm64 app, universal Sparkle internals, strict nested signatures"
if [[ "${GAUGELET_EXPECT_DEVELOPER_ID:-0}" == "1" ]]; then
    print -- "Gatekeeper: Developer ID/notarization path expected and checked separately"
else
    print -- "Gatekeeper: rejection confirmed as expected for the non-notarized community build; this is not Apple verification"
fi
