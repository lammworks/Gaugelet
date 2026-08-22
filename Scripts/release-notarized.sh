#!/bin/zsh

# Dormant future path for an active Apple Developer Program membership.
# It never publishes. It builds Developer ID-signed, notarized, stapled assets
# for a release owner to review and finalize with Sparkle locally.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
INFO_PLIST="${ROOT_DIR}/Packaging/Info.plist"
RELEASE_ROOT="${GAUGELET_NOTARIZED_RELEASE_ROOT:-${ROOT_DIR}/build/notarized-release}"
SIGNING_IDENTITY="${GAUGELET_SIGNING_IDENTITY:-}"
SIGNING_KEYCHAIN="${GAUGELET_SIGNING_KEYCHAIN:-}"
NOTARY_PROFILE="${GAUGELET_NOTARY_PROFILE:-}"
NOTARY_KEYCHAIN="${GAUGELET_NOTARY_KEYCHAIN:-}"
NOTARY_TIMEOUT="${GAUGELET_NOTARY_TIMEOUT:-30m}"
WORK_ROOT=""
MOUNT_ROOT=""
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
    [[ -n "${WORK_ROOT}" && -d "${WORK_ROOT}" ]] && /bin/rm -rf "${WORK_ROOT}"
}
trap cleanup EXIT INT TERM

[[ -n "${SIGNING_IDENTITY}" ]] || fail "GAUGELET_SIGNING_IDENTITY is required"
[[ -n "${NOTARY_PROFILE}" ]] || fail "GAUGELET_NOTARY_PROFILE is required"
[[ -f "${INFO_PLIST}" ]] || fail "missing ${INFO_PLIST}"
[[ -z "$(git -C "${ROOT_DIR}" status --porcelain --untracked-files=normal)" ]] \
    || fail "notarized release requires a clean source tree"
"${SCRIPT_DIR}/verify-sparkle-key-gates.sh" --configuration-only

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
[[ "${VERSION}" == "1.0.1" && "${BUILD}" == "2" ]] \
    || fail "notarized Gaugelet 1.0.1 path expects 1.0.1 (2)"

typeset -a SECURITY_KEYCHAIN_ARGS CODESIGN_KEYCHAIN_ARGS
SECURITY_KEYCHAIN_ARGS=()
CODESIGN_KEYCHAIN_ARGS=()
if [[ -n "${SIGNING_KEYCHAIN}" ]]; then
    [[ -f "${SIGNING_KEYCHAIN}" ]] || fail "signing keychain not found: ${SIGNING_KEYCHAIN}"
    SECURITY_KEYCHAIN_ARGS+=("${SIGNING_KEYCHAIN}")
    CODESIGN_KEYCHAIN_ARGS+=(--keychain "${SIGNING_KEYCHAIN}")
fi
if [[ -n "${NOTARY_KEYCHAIN}" ]]; then
    [[ -f "${NOTARY_KEYCHAIN}" ]] || fail "notary keychain not found: ${NOTARY_KEYCHAIN}"
fi
IDENTITY_LINE="$(/usr/bin/security find-identity -v -p codesigning "${SECURITY_KEYCHAIN_ARGS[@]}" 2>/dev/null \
    | /usr/bin/grep -F -- "${SIGNING_IDENTITY}" \
    | /usr/bin/grep -F 'Developer ID Application:' \
    | /usr/bin/awk 'NR == 1 { print }')"
[[ -n "${IDENTITY_LINE}" ]] || fail "Developer ID Application identity is unavailable"

/usr/bin/install -d "${ROOT_DIR}/build"
RELEASE_PARENT="${RELEASE_ROOT:h}"
/usr/bin/install -d "${RELEASE_PARENT}"
RELEASE_PARENT="${RELEASE_PARENT:A}"
RELEASE_ROOT="${RELEASE_PARENT}/${RELEASE_ROOT:t}"
case "${RELEASE_ROOT}" in
    "${ROOT_DIR}/build/"*) ;;
    *) fail "notarized output must remain under ${ROOT_DIR}/build" ;;
esac

WORK_ROOT="$(/usr/bin/mktemp -d "${ROOT_DIR}/build/.notarized.XXXXXX")"
PRODUCT_ROOT="${WORK_ROOT}/product"
STAGED_ROOT="${WORK_ROOT}/assets"
EVIDENCE_ROOT="${WORK_ROOT}/evidence"
/usr/bin/install -d "${PRODUCT_ROOT}" "${STAGED_ROOT}" "${EVIDENCE_ROOT}"

GAUGELET_OUTPUT_ROOT="${PRODUCT_ROOT}" \
GAUGELET_SIGNING_IDENTITY="${SIGNING_IDENTITY}" \
GAUGELET_SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN}" \
GAUGELET_REQUIRE_ASSET_CATALOG=1 \
    "${SCRIPT_DIR}/package-app.sh"
"${SCRIPT_DIR}/test-source.sh"
"${SCRIPT_DIR}/create-dmg.sh" "${PRODUCT_ROOT}/Gaugelet.app" "${WORK_ROOT}/Gaugelet.dmg"

/usr/bin/codesign --force \
    --sign "${SIGNING_IDENTITY}" \
    "${CODESIGN_KEYCHAIN_ARGS[@]}" \
    --timestamp \
    "${WORK_ROOT}/Gaugelet.dmg"

typeset -a NOTARY_ARGS
NOTARY_ARGS=(--keychain-profile "${NOTARY_PROFILE}")
if [[ -n "${NOTARY_KEYCHAIN}" ]]; then
    NOTARY_ARGS+=(--keychain "${NOTARY_KEYCHAIN}")
fi
if ! /usr/bin/xcrun notarytool submit "${WORK_ROOT}/Gaugelet.dmg" \
    "${NOTARY_ARGS[@]}" \
    --wait \
    --timeout "${NOTARY_TIMEOUT}" \
    --output-format json \
    > "${EVIDENCE_ROOT}/notarization.json" \
    2> "${EVIDENCE_ROOT}/notarization.stderr.log"; then
    /bin/cat "${EVIDENCE_ROOT}/notarization.stderr.log" >&2
    fail "notarytool submission failed"
fi
NOTARY_STATUS="$(/usr/bin/plutil -extract status raw -o - "${EVIDENCE_ROOT}/notarization.json" 2>/dev/null || true)"
NOTARY_ID="$(/usr/bin/plutil -extract id raw -o - "${EVIDENCE_ROOT}/notarization.json" 2>/dev/null || true)"
[[ "${NOTARY_STATUS}" == "Accepted" && -n "${NOTARY_ID}" ]] \
    || fail "notarization was not accepted"
/usr/bin/xcrun stapler staple "${WORK_ROOT}/Gaugelet.dmg"
/usr/bin/xcrun stapler validate "${WORK_ROOT}/Gaugelet.dmg"
/usr/bin/codesign --verify --deep --strict --verbose=4 "${PRODUCT_ROOT}/Gaugelet.app"
/usr/sbin/spctl --assess --type execute --verbose=4 "${PRODUCT_ROOT}/Gaugelet.app"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=4 \
    "${WORK_ROOT}/Gaugelet.dmg"

/usr/bin/ditto --noqtn "${WORK_ROOT}/Gaugelet.dmg" "${STAGED_ROOT}/Gaugelet.dmg"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
    "${PRODUCT_ROOT}/Gaugelet.app.dSYM" \
    "${STAGED_ROOT}/Gaugelet.app.dSYM.zip"
(
    cd "${STAGED_ROOT}"
    /usr/bin/shasum -a 256 Gaugelet.dmg
) > "${STAGED_ROOT}/Gaugelet.dmg.sha256"
/usr/bin/install -m 644 "${EVIDENCE_ROOT}/notarization.json" \
    "${STAGED_ROOT}/notarization.json"

SOURCE_COMMIT="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
CREATED_AT="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
{
    print -- "Gaugelet build evidence"
    print -- "Artifact kind: dormant Developer ID/notarized"
    print -- "Version: ${VERSION}"
    print -- "Build: ${BUILD}"
    print -- "Created UTC: ${CREATED_AT}"
    print -- "Source commit: ${SOURCE_COMMIT}"
    print -- "Source tree dirty: no"
    /bin/cat "${PRODUCT_ROOT}/build-metadata.env"
} > "${STAGED_ROOT}/build-evidence.txt"
DMG_SHA256="$(/usr/bin/awk '{ print $1 }' "${STAGED_ROOT}/Gaugelet.dmg.sha256")"
{
    print -- "Gaugelet Developer ID release evidence"
    print -- "Version: ${VERSION}"
    print -- "Build: ${BUILD}"
    print -- "Developer ID identity: ${SIGNING_IDENTITY}"
    print -- "Hardened runtime: enabled"
    print -- "Notarization status: ${NOTARY_STATUS}"
    print -- "Notarization submission: ${NOTARY_ID}"
    print -- "Staple validation: passed"
    print -- "Gatekeeper app and DMG assessments: passed"
    print -- "DMG SHA-256: ${DMG_SHA256}"
    print -- "Publication: not performed"
} > "${STAGED_ROOT}/release-evidence.txt"

GAUGELET_EXPECT_DEVELOPER_ID=1 \
    "${SCRIPT_DIR}/verify-release.sh" "${STAGED_ROOT}"

BACKUP_ROOT="${ROOT_DIR}/build/.${RELEASE_ROOT:t}.previous.$$"
if [[ -e "${RELEASE_ROOT}" || -L "${RELEASE_ROOT}" ]]; then
    /bin/mv "${RELEASE_ROOT}" "${BACKUP_ROOT}"
fi
if ! /bin/mv "${STAGED_ROOT}" "${RELEASE_ROOT}"; then
    if [[ -e "${BACKUP_ROOT}" || -L "${BACKUP_ROOT}" ]]; then
        /bin/mv "${BACKUP_ROOT}" "${RELEASE_ROOT}"
    fi
    fail "could not publish notarized artifacts locally"
fi
if [[ -e "${BACKUP_ROOT}" || -L "${BACKUP_ROOT}" ]]; then
    /bin/rm -rf "${BACKUP_ROOT}"
fi

print -- "Dormant Developer ID artifacts ready in ${RELEASE_ROOT}"
print -- "No GitHub release was created or modified."
