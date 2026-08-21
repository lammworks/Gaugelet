#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
INFO_PLIST="${ROOT_DIR}/Packaging/Info.plist"
ICON_FILE="${ROOT_DIR}/Packaging/Gaugelet.icns"
ASSET_CATALOG="${ROOT_DIR}/Assets/Assets.xcassets"
ICON_VARIANT_ROOT="${ROOT_DIR}/Assets/IconVariants"
OUTPUT_ROOT="${GAUGELET_OUTPUT_ROOT:-${ROOT_DIR}/build/product}"
SWIFTPM_BUILD_ROOT="${GAUGELET_SWIFTPM_BUILD_ROOT:-${ROOT_DIR}/.build}"
SPARKLE_FRAMEWORK_OVERRIDE="${GAUGELET_SPARKLE_FRAMEWORK:-}"
SIGNING_IDENTITY="${GAUGELET_SIGNING_IDENTITY:-}"
SIGNING_KEYCHAIN="${GAUGELET_SIGNING_KEYCHAIN:-}"
REQUIRE_ASSET_CATALOG="${GAUGELET_REQUIRE_ASSET_CATALOG:-0}"
APP_NAME="Gaugelet"
EXECUTABLE_NAME="Gaugelet"
MINIMUM_MACOS="14.0"
DESIRED_RPATH="@executable_path/../Frameworks"

fail() {
    print -u2 -- "error: $*"
    exit 1
}

[[ -f "${INFO_PLIST}" ]] || fail "missing ${INFO_PLIST}"
[[ -f "${ROOT_DIR}/Package.swift" ]] || fail "missing Package.swift"
[[ -f "${ROOT_DIR}/Package.resolved" ]] || fail "missing Package.resolved"
[[ -f "${ICON_FILE}" ]] || fail "missing ${ICON_FILE}; run Scripts/generate-icon.sh"
[[ -d "${ASSET_CATALOG}" ]] || fail "missing ${ASSET_CATALOG}"
/usr/bin/plutil -lint "${INFO_PLIST}" >/dev/null
"${SCRIPT_DIR}/verify-sparkle-pin.py"

typeset -a ICON_STYLES
ICON_STYLES=(Core Aurora Ember Moss Monochrome 8Bit Pride)
for style in "${ICON_STYLES[@]}"; do
    [[ -f "${ICON_VARIANT_ROOT}/GaugeletIcon-${style}-1024.png" ]] \
        || fail "missing in-app icon variant: ${style}"
done

BUNDLE_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${INFO_PLIST}")"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO_PLIST}")"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
BUNDLE_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
BUNDLE_MINIMUM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${INFO_PLIST}")"

[[ "${BUNDLE_EXECUTABLE}" == "${EXECUTABLE_NAME}" ]] || fail "CFBundleExecutable must be ${EXECUTABLE_NAME}"
[[ "${BUNDLE_IDENTIFIER}" == "com.lammworks.gaugelet" ]] || fail "unexpected bundle identifier: ${BUNDLE_IDENTIFIER}"
[[ "${BUNDLE_MINIMUM}" == "${MINIMUM_MACOS}" ]] || fail "script and Info.plist minimum macOS versions differ"

/usr/bin/install -d "${OUTPUT_ROOT}" "${SWIFTPM_BUILD_ROOT}"
OUTPUT_ROOT="${OUTPUT_ROOT:A}"
SWIFTPM_BUILD_ROOT="${SWIFTPM_BUILD_ROOT:A}"
[[ "${OUTPUT_ROOT}" != "/" && "${OUTPUT_ROOT}" != "${ROOT_DIR}" ]] \
    || fail "refusing unsafe output directory: ${OUTPUT_ROOT}"
[[ "${SWIFTPM_BUILD_ROOT}" != "/" && "${SWIFTPM_BUILD_ROOT}" != "${ROOT_DIR}" ]] \
    || fail "refusing unsafe SwiftPM build directory: ${SWIFTPM_BUILD_ROOT}"

APP_PATH="${OUTPUT_ROOT}/${APP_NAME}.app"
DSYM_PATH="${OUTPUT_ROOT}/${APP_NAME}.app.dSYM"
LOCK_DIR="${OUTPUT_ROOT}/.package-app.lock"
LOCK_HELD=0
STAGING_ROOT=""

if ! /bin/mkdir "${LOCK_DIR}" 2>/dev/null; then
    fail "another package-app process is using ${OUTPUT_ROOT}; remove ${LOCK_DIR} only if no build is running"
fi
LOCK_HELD=1
print -- "$$" > "${LOCK_DIR}/pid"

STAGING_ROOT="$(/usr/bin/mktemp -d "${OUTPUT_ROOT}/.package-app.XXXXXX")"
STAGING_APP="${STAGING_ROOT}/${APP_NAME}.app"
STAGING_DSYM="${STAGING_ROOT}/${APP_NAME}.app.dSYM"

cleanup() {
    if [[ -n "${STAGING_ROOT}" && -d "${STAGING_ROOT}" ]]; then
        /bin/rm -rf "${STAGING_ROOT}"
    fi
    if (( LOCK_HELD )) && [[ -d "${LOCK_DIR}" ]]; then
        /bin/rm -rf "${LOCK_DIR}"
    fi
}
trap cleanup EXIT INT TERM

SELECTED_DEVELOPER_DIR="$("${SCRIPT_DIR}/select-developer-dir.sh")"
MODULE_CACHE_ROOT="${SWIFTPM_BUILD_ROOT}/ModuleCache"
SWIFTPM_CACHE_ROOT="${SWIFTPM_BUILD_ROOT}/Cache"
/usr/bin/install -d "${MODULE_CACHE_ROOT}" "${SWIFTPM_CACHE_ROOT}"
SWIFT="${GAUGELET_SWIFT:-$(DEVELOPER_DIR="${SELECTED_DEVELOPER_DIR}" /usr/bin/xcrun --find swift 2>/dev/null || true)}"
DSYMUTIL="$(DEVELOPER_DIR="${SELECTED_DEVELOPER_DIR}" /usr/bin/xcrun --find dsymutil 2>/dev/null || true)"
STRIP="$(DEVELOPER_DIR="${SELECTED_DEVELOPER_DIR}" /usr/bin/xcrun --find strip 2>/dev/null || true)"
LIPO="$(DEVELOPER_DIR="${SELECTED_DEVELOPER_DIR}" /usr/bin/xcrun --find lipo 2>/dev/null || true)"
OTOOL="$(DEVELOPER_DIR="${SELECTED_DEVELOPER_DIR}" /usr/bin/xcrun --find otool 2>/dev/null || true)"
INSTALL_NAME_TOOL="$(DEVELOPER_DIR="${SELECTED_DEVELOPER_DIR}" /usr/bin/xcrun --find install_name_tool 2>/dev/null || true)"
[[ -x "${SWIFT}" ]] || fail "SwiftPM is unavailable; install/select Xcode or Command Line Tools"
[[ -x "${DSYMUTIL}" && -x "${STRIP}" && -x "${LIPO}" ]] \
    || fail "required Apple binary tools are unavailable"
[[ -x "${OTOOL}" && -x "${INSTALL_NAME_TOOL}" ]] \
    || fail "otool/install_name_tool are unavailable"

typeset -a SWIFT_BUILD_ARGS
SWIFT_BUILD_ARGS=(
    --package-path "${ROOT_DIR}"
    --scratch-path "${SWIFTPM_BUILD_ROOT}"
    --configuration release
    --arch arm64
    --product Gaugelet
    --disable-automatic-resolution
    --disable-sandbox
    -Xswiftc -g
)

DEVELOPER_DIR="${SELECTED_DEVELOPER_DIR}" \
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_ROOT}" \
SWIFT_MODULE_CACHE_PATH="${MODULE_CACHE_ROOT}" \
SWIFTPM_MODULECACHE_OVERRIDE="${MODULE_CACHE_ROOT}" \
XDG_CACHE_HOME="${SWIFTPM_CACHE_ROOT}" \
    "${SWIFT}" build "${SWIFT_BUILD_ARGS[@]}"
BIN_PATH="$(DEVELOPER_DIR="${SELECTED_DEVELOPER_DIR}" \
    CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_ROOT}" \
    SWIFT_MODULE_CACHE_PATH="${MODULE_CACHE_ROOT}" \
    SWIFTPM_MODULECACHE_OVERRIDE="${MODULE_CACHE_ROOT}" \
    XDG_CACHE_HOME="${SWIFTPM_CACHE_ROOT}" \
    "${SWIFT}" build \
    --package-path "${ROOT_DIR}" \
    --scratch-path "${SWIFTPM_BUILD_ROOT}" \
    --configuration release \
    --arch arm64 \
    --disable-automatic-resolution \
    --disable-sandbox \
    --show-bin-path)"
SOURCE_EXECUTABLE="${BIN_PATH}/${EXECUTABLE_NAME}"
[[ -x "${SOURCE_EXECUTABLE}" ]] || fail "SwiftPM did not produce ${SOURCE_EXECUTABLE}"
[[ "$("${LIPO}" -archs "${SOURCE_EXECUTABLE}")" == "arm64" ]] \
    || fail "SwiftPM Gaugelet product must contain only arm64"

SPARKLE_FRAMEWORK_SOURCE="${SPARKLE_FRAMEWORK_OVERRIDE}"
if [[ -n "${SPARKLE_FRAMEWORK_SOURCE}" ]]; then
    [[ -d "${SPARKLE_FRAMEWORK_SOURCE}" ]] \
        || fail "GAUGELET_SPARKLE_FRAMEWORK is not a directory: ${SPARKLE_FRAMEWORK_SOURCE}"
    SPARKLE_FRAMEWORK_SOURCE="${SPARKLE_FRAMEWORK_SOURCE:A}"
else
    typeset -a SPARKLE_FRAMEWORK_CANDIDATES
    SPARKLE_FRAMEWORK_CANDIDATES=()
    while IFS= read -r framework; do
        SPARKLE_FRAMEWORK_CANDIDATES+=("${framework}")
    done < <(/usr/bin/find "${SWIFTPM_BUILD_ROOT}/artifacts" \
        -type d -name Sparkle.framework -print 2>/dev/null | /usr/bin/sort)
    (( ${#SPARKLE_FRAMEWORK_CANDIDATES[@]} == 1 )) \
        || fail "expected one SwiftPM Sparkle.framework artifact, found ${#SPARKLE_FRAMEWORK_CANDIDATES[@]}"
    SPARKLE_FRAMEWORK_SOURCE="${SPARKLE_FRAMEWORK_CANDIDATES[1]}"
fi
"${SCRIPT_DIR}/verify-sparkle-framework.sh" "${SPARKLE_FRAMEWORK_SOURCE}"

/usr/bin/install -d "${STAGING_APP}/Contents/MacOS"
/usr/bin/install -d "${STAGING_APP}/Contents/Resources"
/usr/bin/install -d "${STAGING_APP}/Contents/Frameworks"
/usr/bin/ditto --noqtn "${SOURCE_EXECUTABLE}" "${STAGING_APP}/Contents/MacOS/${EXECUTABLE_NAME}"
/usr/bin/ditto --noqtn "${SPARKLE_FRAMEWORK_SOURCE}" \
    "${STAGING_APP}/Contents/Frameworks/Sparkle.framework"
/bin/chmod 755 "${STAGING_APP}/Contents/MacOS/${EXECUTABLE_NAME}"
"${SCRIPT_DIR}/verify-sparkle-framework.sh" \
    "${STAGING_APP}/Contents/Frameworks/Sparkle.framework" \
    "${SPARKLE_FRAMEWORK_SOURCE}"

PACKAGED_EXECUTABLE="${STAGING_APP}/Contents/MacOS/${EXECUTABLE_NAME}"
typeset -a CURRENT_RPATHS
CURRENT_RPATHS=()
while IFS= read -r rpath; do
    [[ -n "${rpath}" ]] && CURRENT_RPATHS+=("${rpath}")
done < <("${OTOOL}" -l "${PACKAGED_EXECUTABLE}" \
    | /usr/bin/awk '$1 == "cmd" && $2 == "LC_RPATH" { want = 1; next } want && $1 == "path" { print $2; want = 0 }')

HAS_DESIRED_RPATH=0
for rpath in "${CURRENT_RPATHS[@]}"; do
    if [[ "${rpath}" == "${DESIRED_RPATH}" ]]; then
        HAS_DESIRED_RPATH=1
    else
        "${INSTALL_NAME_TOOL}" -delete_rpath "${rpath}" "${PACKAGED_EXECUTABLE}"
    fi
done
if (( ! HAS_DESIRED_RPATH )); then
    "${INSTALL_NAME_TOOL}" -add_rpath "${DESIRED_RPATH}" "${PACKAGED_EXECUTABLE}"
fi

PACKAGED_RPATHS="$("${OTOOL}" -l "${PACKAGED_EXECUTABLE}" \
    | /usr/bin/awk '$1 == "cmd" && $2 == "LC_RPATH" { want = 1; next } want && $1 == "path" { print $2; want = 0 }')"
[[ "${PACKAGED_RPATHS}" == "${DESIRED_RPATH}" ]] \
    || fail "Gaugelet must have exactly one rpath (${DESIRED_RPATH}); found: ${PACKAGED_RPATHS:-none}"
"${OTOOL}" -L "${PACKAGED_EXECUTABLE}" \
    | /usr/bin/grep -F '@rpath/Sparkle.framework/' >/dev/null \
    || fail "Gaugelet does not link Sparkle through @rpath"
if "${OTOOL}" -L "${PACKAGED_EXECUTABLE}" | /usr/bin/grep -F -- "${SWIFTPM_BUILD_ROOT}" >/dev/null; then
    fail "Gaugelet retains a build-directory Sparkle load path"
fi

"${DSYMUTIL}" "${PACKAGED_EXECUTABLE}" -o "${STAGING_DSYM}"
[[ -d "${STAGING_DSYM}" ]] || fail "dsymutil did not create ${APP_NAME}.app.dSYM"
/usr/bin/dwarfdump --uuid "${STAGING_DSYM}" > "${STAGING_ROOT}/dsym-uuids.txt"
/usr/bin/grep -F '(arm64)' "${STAGING_ROOT}/dsym-uuids.txt" >/dev/null \
    || fail "dSYM is missing the arm64 UUID"
if /usr/bin/grep -F '(x86_64)' "${STAGING_ROOT}/dsym-uuids.txt" >/dev/null; then
    fail "dSYM unexpectedly contains x86_64"
fi
"${STRIP}" -S "${PACKAGED_EXECUTABLE}"

/usr/bin/install -m 644 "${INFO_PLIST}" "${STAGING_APP}/Contents/Info.plist"
for style in "${ICON_STYLES[@]}"; do
    /usr/bin/sips -z 256 256 \
        "${ICON_VARIANT_ROOT}/GaugeletIcon-${style}-1024.png" \
        --out "${STAGING_APP}/Contents/Resources/GaugeletIcon-${style}-256.png" >/dev/null
done

ASSET_CATALOG_KIND="fallback-icns"
ACTOOL="${GAUGELET_ACTOOL:-$(DEVELOPER_DIR="${SELECTED_DEVELOPER_DIR}" /usr/bin/xcrun --find actool 2>/dev/null || true)}"
if [[ -n "${ACTOOL}" && ! -x "${ACTOOL}" ]]; then
    fail "GAUGELET_ACTOOL is not executable: ${ACTOOL}"
fi
if [[ -z "${ACTOOL}" ]]; then
    ACTOOL="$(/usr/bin/find /Applications \
        -path '*/Xcode*.app/Contents/Developer/usr/bin/actool' \
        -type f -perm -111 -print 2>/dev/null \
        | /usr/bin/sort -r \
        | /usr/bin/awk 'NR == 1 { print }')"
fi
if [[ -n "${ACTOOL}" ]]; then
    ASSET_OUTPUT="${STAGING_ROOT}/compiled-assets"
    ASSET_INFO="${STAGING_ROOT}/assetcatalog-generated-info.plist"
    /usr/bin/install -d "${ASSET_OUTPUT}"
    "${ACTOOL}" "${ASSET_CATALOG}" \
        --compile "${ASSET_OUTPUT}" \
        --app-icon AppIcon \
        --target-device mac \
        --minimum-deployment-target "${MINIMUM_MACOS}" \
        --platform macosx \
        --bundle-identifier "${BUNDLE_IDENTIFIER}" \
        --development-region en \
        --enable-on-demand-resources NO \
        --compress-pngs \
        --output-partial-info-plist "${ASSET_INFO}" \
        --output-format human-readable-text \
        --notices --warnings --errors
    [[ -s "${ASSET_OUTPUT}/Assets.car" && -s "${ASSET_OUTPUT}/AppIcon.icns" ]] \
        || fail "actool did not produce Assets.car and AppIcon.icns"
    /usr/bin/install -m 644 "${ASSET_OUTPUT}/Assets.car" \
        "${STAGING_APP}/Contents/Resources/Assets.car"
    /usr/bin/install -m 644 "${ASSET_OUTPUT}/AppIcon.icns" \
        "${STAGING_APP}/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c 'Delete :CFBundleIconName' "${STAGING_APP}/Contents/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c 'Add :CFBundleIconName string AppIcon' "${STAGING_APP}/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile AppIcon' "${STAGING_APP}/Contents/Info.plist"
    ASSET_CATALOG_KIND="compiled"
else
    [[ "${REQUIRE_ASSET_CATALOG}" != "1" ]] \
        || fail "Xcode actool is required for a release build"
    /usr/bin/install -m 644 "${ICON_FILE}" "${STAGING_APP}/Contents/Resources/Gaugelet.icns"
    print -u2 -- "warning: actool unavailable; using the local-development ICNS fallback"
fi
print -n -- 'APPL????' > "${STAGING_APP}/Contents/PkgInfo"
/usr/bin/plutil -lint "${STAGING_APP}/Contents/Info.plist" >/dev/null

typeset -a CODESIGN_BASE_ARGS
CODESIGN_BASE_ARGS=(--force)
SIGNATURE_KIND="ad-hoc"
if [[ -n "${SIGNING_IDENTITY}" ]]; then
    typeset -a SECURITY_KEYCHAIN_ARGS
    SECURITY_KEYCHAIN_ARGS=()
    if [[ -n "${SIGNING_KEYCHAIN}" ]]; then
        [[ -f "${SIGNING_KEYCHAIN}" ]] || fail "signing keychain not found: ${SIGNING_KEYCHAIN}"
        SECURITY_KEYCHAIN_ARGS+=("${SIGNING_KEYCHAIN}")
        CODESIGN_BASE_ARGS+=(--keychain "${SIGNING_KEYCHAIN}")
    fi
    IDENTITY_LINE="$(/usr/bin/security find-identity -v -p codesigning "${SECURITY_KEYCHAIN_ARGS[@]}" 2>/dev/null \
        | /usr/bin/grep -F -- "${SIGNING_IDENTITY}" \
        | /usr/bin/grep -F 'Developer ID Application:' \
        | /usr/bin/awk 'NR == 1 { print }')"
    [[ -n "${IDENTITY_LINE}" ]] \
        || fail "GAUGELET_SIGNING_IDENTITY is not an available Developer ID Application identity"
    CODESIGN_BASE_ARGS+=(--sign "${SIGNING_IDENTITY}" --options runtime --timestamp)
    SIGNATURE_KIND="Developer ID Application"
else
    CODESIGN_BASE_ARGS+=(--sign - --timestamp=none)
fi

sign_nested_code() {
    local path="$1"
    /usr/bin/codesign "${CODESIGN_BASE_ARGS[@]}" \
        --preserve-metadata=identifier,entitlements \
        "${path}"
}

SPARKLE_DESTINATION="${STAGING_APP}/Contents/Frameworks/Sparkle.framework"
while IFS= read -r -d '' item; do
    if /usr/bin/file -b "${item}" | /usr/bin/grep -F 'Mach-O' >/dev/null; then
        sign_nested_code "${item}"
    fi
done < <(/usr/bin/find "${SPARKLE_DESTINATION}" -type f -print0)
while IFS= read -r bundle; do
    sign_nested_code "${bundle}"
done < <(/usr/bin/find "${SPARKLE_DESTINATION}" -depth -type d \
    \( -name '*.app' -o -name '*.xpc' \) -print)
sign_nested_code "${SPARKLE_DESTINATION}"
/usr/bin/codesign "${CODESIGN_BASE_ARGS[@]}" "${STAGING_APP}"

/usr/bin/codesign --verify --deep --strict --verbose=2 "${STAGING_APP}"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${SPARKLE_DESTINATION}"
/usr/bin/codesign -d --verbose=4 "${STAGING_APP}" > "${STAGING_ROOT}/signature.txt" 2>&1
if [[ "${SIGNATURE_KIND}" == "Developer ID Application" ]]; then
    /usr/bin/grep -F 'Authority=Developer ID Application:' "${STAGING_ROOT}/signature.txt" >/dev/null \
        || fail "the app was not signed by a Developer ID Application certificate"
    /usr/bin/grep -F 'Timestamp=' "${STAGING_ROOT}/signature.txt" >/dev/null \
        || fail "the Developer ID signature does not contain a secure timestamp"
    /usr/bin/grep -F 'runtime' "${STAGING_ROOT}/signature.txt" >/dev/null \
        || fail "Developer ID build is missing hardened runtime"
else
    /usr/bin/grep -F 'Signature=adhoc' "${STAGING_ROOT}/signature.txt" >/dev/null \
        || fail "community build is not ad-hoc signed"
    if /usr/bin/grep -F 'runtime' "${STAGING_ROOT}/signature.txt" >/dev/null; then
        fail "community app must not enable hardened runtime/library validation"
    fi
fi

publish_directory() {
    local source="$1"
    local destination="$2"
    local backup="${OUTPUT_ROOT}/.${destination:t}.previous.$$"
    if [[ -e "${destination}" || -L "${destination}" ]]; then
        /bin/mv "${destination}" "${backup}"
    fi
    if ! /bin/mv "${source}" "${destination}"; then
        if [[ -e "${backup}" || -L "${backup}" ]]; then
            /bin/mv "${backup}" "${destination}"
        fi
        return 1
    fi
    if [[ -e "${backup}" || -L "${backup}" ]]; then
        /bin/rm -rf "${backup}"
    fi
}

publish_directory "${STAGING_APP}" "${APP_PATH}"
publish_directory "${STAGING_DSYM}" "${DSYM_PATH}"

SDK_PATH="$(DEVELOPER_DIR="${SELECTED_DEVELOPER_DIR}" /usr/bin/xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(DEVELOPER_DIR="${SELECTED_DEVELOPER_DIR}" /usr/bin/xcrun --sdk macosx --show-sdk-version)"
SWIFTC_PATH="$(DEVELOPER_DIR="${SELECTED_DEVELOPER_DIR}" /usr/bin/xcrun --find swiftc)"
SWIFT_VERSION="$("${SWIFT}" --version 2>&1 | /usr/bin/awk 'NR == 1 { print }')"
SPARKLE_REVISION="$(/usr/bin/python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); print(next(x["state"]["revision"] for x in p["pins"] if x["identity"]=="sparkle"))' "${ROOT_DIR}/Package.resolved")"
METADATA_TEMP="${OUTPUT_ROOT}/.build-metadata.env.tmp.$$"
{
    print -- "APP_NAME=${APP_NAME}"
    print -- "BUNDLE_IDENTIFIER=${BUNDLE_IDENTIFIER}"
    print -- "VERSION=${BUNDLE_VERSION}"
    print -- "BUILD=${BUNDLE_BUILD}"
    print -- "MINIMUM_MACOS=${MINIMUM_MACOS}"
    print -- "ARCHITECTURES=arm64"
    print -- "SDK_PATH=${SDK_PATH}"
    print -- "SDK_VERSION=${SDK_VERSION}"
    print -- "DEVELOPER_DIR=${SELECTED_DEVELOPER_DIR}"
    print -- "SWIFTC_PATH=${SWIFTC_PATH}"
    print -- "SWIFT_VERSION=${SWIFT_VERSION}"
    print -- "SPARKLE_VERSION=2.9.5"
    print -- "SPARKLE_REVISION=${SPARKLE_REVISION}"
    print -- "SPARKLE_RPATH=${DESIRED_RPATH}"
    print -- "SIGNATURE_KIND=${SIGNATURE_KIND}"
    print -- "ASSET_CATALOG=${ASSET_CATALOG_KIND}"
} > "${METADATA_TEMP}"
/bin/mv -f "${METADATA_TEMP}" "${OUTPUT_ROOT}/build-metadata.env"

print -- "Built ${APP_PATH}"
print -- "dSYM ${DSYM_PATH}"
print -- "Main executable architecture: $("${LIPO}" -archs "${APP_PATH}/Contents/MacOS/${EXECUTABLE_NAME}")"
print -- "Sparkle framework: 2.9.5 vendor universal binaries preserved"
print -- "Signature: ${SIGNATURE_KIND}"
