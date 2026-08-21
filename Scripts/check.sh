#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
INFO_PLIST="${ROOT_DIR}/Packaging/Info.plist"
ASSET_CATALOG="${ROOT_DIR}/Assets/Assets.xcassets"
APP_ICON_SET="${ASSET_CATALOG}/AppIcon.appiconset"
ICON_VARIANT_ROOT="${ROOT_DIR}/Assets/IconVariants"
CANDIDATE_ROOT="${ROOT_DIR}/build/candidate"

fail() {
    print -u2 -- "error: $*"
    exit 1
}

assert_plist_value() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(/usr/libexec/PlistBuddy -c "Print :${key}" "${INFO_PLIST}")"
    [[ "${actual}" == "${expected}" ]] || fail "${key} is ${actual}, expected ${expected}"
}

assert_plist_absent() {
    local key="$1"
    if /usr/libexec/PlistBuddy -c "Print :${key}" "${INFO_PLIST}" >/dev/null 2>&1; then
        fail "${key} must be absent so Sparkle asks for automatic-check consent"
    fi
}

assert_png_dimensions() {
    local image_path="$1"
    local expected="$2"
    local width
    local height
    [[ -f "${image_path}" ]] || fail "missing PNG: ${image_path}"
    width="$(/usr/bin/sips -g pixelWidth "${image_path}" 2>/dev/null \
        | /usr/bin/awk '/pixelWidth:/ { print $2 }')"
    height="$(/usr/bin/sips -g pixelHeight "${image_path}" 2>/dev/null \
        | /usr/bin/awk '/pixelHeight:/ { print $2 }')"
    [[ "${width}x${height}" == "${expected}x${expected}" ]] \
        || fail "${image_path} is ${width:-unknown}x${height:-unknown}, expected ${expected}x${expected}"
}

cd "${ROOT_DIR}"
/usr/bin/plutil -lint "${INFO_PLIST}" >/dev/null
assert_plist_value CFBundleDisplayName Gaugelet
assert_plist_value CFBundleExecutable Gaugelet
assert_plist_value CFBundleIdentifier com.lammworks.gaugelet
assert_plist_value CFBundleName Gaugelet
assert_plist_value CFBundleShortVersionString 1.0.0
assert_plist_value CFBundleVersion 1
assert_plist_value LSApplicationCategoryType public.app-category.utilities
assert_plist_value LSMinimumSystemVersion 14.0
assert_plist_value SUFeedURL 'https://github.com/lammworks/Gaugelet/releases/latest/download/appcast.xml'
assert_plist_value SUVerifyUpdateBeforeExtraction true
assert_plist_value SURequireSignedFeed true
assert_plist_value SUEnableSystemProfiling false
assert_plist_value SUScheduledCheckInterval 86400
assert_plist_value SUAutomaticallyUpdate false
assert_plist_value SUAllowsAutomaticUpdates false
assert_plist_absent SUEnableAutomaticChecks

PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${INFO_PLIST}")"
if [[ "${PUBLIC_KEY}" != *RELEASE_BLOCKED* && "${PUBLIC_KEY}" != *PLACEHOLDER* ]]; then
    "${SCRIPT_DIR}/verify-sparkle-key-gates.sh" --configuration-only
else
    print -u2 -- "warning: SUPublicEDKey is a release-blocking placeholder; development checks continue, release.sh will not"
fi
"${SCRIPT_DIR}/verify-sparkle-pin.py"

[[ -d "${APP_ICON_SET}" ]] || fail "missing AppIcon asset catalog"
/usr/bin/plutil -convert binary1 -o /dev/null "${ASSET_CATALOG}/Contents.json"
/usr/bin/plutil -convert binary1 -o /dev/null "${APP_ICON_SET}/Contents.json"
[[ "$(/usr/bin/plutil -extract images raw -o - "${APP_ICON_SET}/Contents.json")" == "10" ]] \
    || fail "AppIcon asset catalog must contain ten macOS slots"

typeset -a APP_ICON_FILES APP_ICON_PIXELS
APP_ICON_FILES=(
    AppIcon-16.png AppIcon-16@2x.png
    AppIcon-32.png AppIcon-32@2x.png
    AppIcon-128.png AppIcon-128@2x.png
    AppIcon-256.png AppIcon-256@2x.png
    AppIcon-512.png AppIcon-512@2x.png
)
APP_ICON_PIXELS=(16 32 32 64 128 256 256 512 512 1024)
for (( index = 1; index <= ${#APP_ICON_FILES[@]}; index++ )); do
    assert_png_dimensions "${APP_ICON_SET}/${APP_ICON_FILES[index]}" "${APP_ICON_PIXELS[index]}"
done

for style in Core Aurora Ember Moss Monochrome 8Bit Pride; do
    assert_png_dimensions "${ICON_VARIANT_ROOT}/GaugeletIcon-${style}-1024.png" 1024
done

/usr/bin/install -d "${ROOT_DIR}/.build"
CHECK_ROOT="$(/usr/bin/mktemp -d "${ROOT_DIR}/.build/icon-check.XXXXXX")"
cleanup() {
    [[ -d "${CHECK_ROOT}" ]] && /bin/rm -rf "${CHECK_ROOT}"
}
trap cleanup EXIT INT TERM
"${SCRIPT_DIR}/generate-icon.sh" "${CHECK_ROOT}/Gaugelet.icns" >/dev/null
/usr/bin/cmp "${CHECK_ROOT}/Gaugelet.icns" "${ROOT_DIR}/Packaging/Gaugelet.icns" \
    || fail "Packaging/Gaugelet.icns is stale; run Scripts/generate-icon.sh"

GAUGELET_ARTIFACT_KIND=candidate \
GAUGELET_CANDIDATE_ROOT="${CANDIDATE_ROOT}" \
GAUGELET_REQUIRE_ASSET_CATALOG="${GAUGELET_REQUIRE_ASSET_CATALOG:-1}" \
    "${SCRIPT_DIR}/build-candidate.sh"
"${SCRIPT_DIR}/verify-release.sh" "${CANDIDATE_ROOT}"

print -- "Gaugelet checks passed"
print -- "Candidate: ${CANDIDATE_ROOT}/Gaugelet.dmg"
print -- "Main executable: arm64"
print -- "Sparkle helpers/framework: vendor universal binaries preserved"
print -- "Gatekeeper rejection: expected and verified; this build is not Apple-verified"
