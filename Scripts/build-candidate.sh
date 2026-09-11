#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
INFO_PLIST="${ROOT_DIR}/Packaging/Info.plist"
ARTIFACT_KIND="${GAUGELET_ARTIFACT_KIND:-candidate}"
OUTPUT_ROOT="${GAUGELET_CANDIDATE_ROOT:-${ROOT_DIR}/build/candidate}"
WORK_ROOT=""

fail() {
    print -u2 -- "error: $*"
    exit 1
}

case "${ARTIFACT_KIND}" in
    candidate|community-release) ;;
    *) fail "GAUGELET_ARTIFACT_KIND must be candidate or community-release" ;;
esac
[[ -f "${INFO_PLIST}" ]] || fail "missing ${INFO_PLIST}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
[[ "${VERSION}" == "1.1.0" && "${BUILD}" == "3" ]] \
    || fail "Gaugelet 1.1.0 release tooling expects 1.1.0 (3); found ${VERSION} (${BUILD})"

if [[ "${ARTIFACT_KIND}" == "community-release" ]]; then
    "${SCRIPT_DIR}/verify-sparkle-key-gates.sh" --configuration-only
fi

/usr/bin/install -d "${ROOT_DIR}/build"
OUTPUT_PARENT="${OUTPUT_ROOT:h}"
/usr/bin/install -d "${OUTPUT_PARENT}"
OUTPUT_PARENT="${OUTPUT_PARENT:A}"
OUTPUT_ROOT="${OUTPUT_PARENT}/${OUTPUT_ROOT:t}"
case "${OUTPUT_ROOT}" in
    "${ROOT_DIR}/build/"*) ;;
    *) fail "artifact output must remain under ${ROOT_DIR}/build" ;;
esac
[[ "${OUTPUT_ROOT}" != "${ROOT_DIR}/build" ]] || fail "refusing to replace the entire build directory"

LOCK_DIR="${ROOT_DIR}/build/.${OUTPUT_ROOT:t}.lock"
if ! /bin/mkdir "${LOCK_DIR}" 2>/dev/null; then
    fail "another ${ARTIFACT_KIND} build is running"
fi
WORK_ROOT="$(/usr/bin/mktemp -d "${ROOT_DIR}/build/.${ARTIFACT_KIND}.XXXXXX")"
PRODUCT_ROOT="${WORK_ROOT}/product"
STAGED_ROOT="${WORK_ROOT}/assets"
/usr/bin/install -d "${PRODUCT_ROOT}" "${STAGED_ROOT}"

cleanup() {
    [[ -n "${WORK_ROOT}" && -d "${WORK_ROOT}" ]] && /bin/rm -rf "${WORK_ROOT}"
    [[ -d "${LOCK_DIR}" ]] && /bin/rm -rf "${LOCK_DIR}"
}
trap cleanup EXIT INT TERM

GAUGELET_OUTPUT_ROOT="${PRODUCT_ROOT}" \
GAUGELET_SIGNING_IDENTITY="" \
GAUGELET_SIGNING_KEYCHAIN="" \
GAUGELET_REQUIRE_ASSET_CATALOG="${GAUGELET_REQUIRE_ASSET_CATALOG:-1}" \
    "${SCRIPT_DIR}/package-app.sh"
"${SCRIPT_DIR}/test-source.sh"
"${SCRIPT_DIR}/create-dmg.sh" "${PRODUCT_ROOT}/Gaugelet.app" "${STAGED_ROOT}/Gaugelet.dmg"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
    "${PRODUCT_ROOT}/Gaugelet.app.dSYM" \
    "${STAGED_ROOT}/Gaugelet.app.dSYM.zip"
(
    cd "${STAGED_ROOT}"
    /usr/bin/shasum -a 256 Gaugelet.dmg
) > "${STAGED_ROOT}/Gaugelet.dmg.sha256"

SOURCE_COMMIT="$(git -C "${ROOT_DIR}" rev-parse HEAD 2>/dev/null || print unknown)"
SOURCE_DIRTY="no"
if [[ -n "$(git -C "${ROOT_DIR}" status --porcelain --untracked-files=normal 2>/dev/null || true)" ]]; then
    SOURCE_DIRTY="yes"
fi
CREATED_AT="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
DMG_SHA256="$(/usr/bin/awk '{ print $1 }' "${STAGED_ROOT}/Gaugelet.dmg.sha256")"
{
    print -- "Gaugelet build evidence"
    print -- "Artifact kind: ${ARTIFACT_KIND}"
    print -- "Version: ${VERSION}"
    print -- "Build: ${BUILD}"
    print -- "Created UTC: ${CREATED_AT}"
    print -- "Source commit: ${SOURCE_COMMIT}"
    print -- "Source tree dirty: ${SOURCE_DIRTY}"
    /bin/cat "${PRODUCT_ROOT}/build-metadata.env"
} > "${STAGED_ROOT}/build-evidence.txt"
{
    print -- "Gaugelet community release evidence"
    print -- "Version: ${VERSION}"
    print -- "Build: ${BUILD}"
    print -- "Main executable: arm64"
    print -- "Sparkle: 2.9.6; vendor universal helper/framework binaries retained"
    print -- "Code signature: ad-hoc, nested inside-out, strict verification required"
    print -- "Hardened runtime: disabled for the community build"
    print -- "Apple notarization: not performed"
    print -- "Apple verification: not claimed"
    print -- "Gatekeeper: rejection expected; users require Privacy & Security -> Open Anyway"
    print -- "Update archive: full Gaugelet.dmg only; deltas disabled"
    print -- "Sparkle appcast: not generated in CI; must be finalized locally from this exact DMG"
    print -- "DMG SHA-256: ${DMG_SHA256}"
} > "${STAGED_ROOT}/release-evidence.txt"

"${SCRIPT_DIR}/verify-release.sh" "${STAGED_ROOT}"

BACKUP_ROOT="${ROOT_DIR}/build/.${OUTPUT_ROOT:t}.previous.$$"
if [[ -e "${OUTPUT_ROOT}" || -L "${OUTPUT_ROOT}" ]]; then
    /bin/mv "${OUTPUT_ROOT}" "${BACKUP_ROOT}"
fi
if ! /bin/mv "${STAGED_ROOT}" "${OUTPUT_ROOT}"; then
    if [[ -e "${BACKUP_ROOT}" || -L "${BACKUP_ROOT}" ]]; then
        /bin/mv "${BACKUP_ROOT}" "${OUTPUT_ROOT}"
    fi
    fail "could not publish generated artifact directory"
fi
if [[ -e "${BACKUP_ROOT}" || -L "${BACKUP_ROOT}" ]]; then
    /bin/rm -rf "${BACKUP_ROOT}"
fi

print -- "${ARTIFACT_KIND} assets ready in ${OUTPUT_ROOT}"
print -- "Gaugelet.dmg SHA-256: ${DMG_SHA256}"
