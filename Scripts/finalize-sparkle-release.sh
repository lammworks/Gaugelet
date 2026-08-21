#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
INFO_PLIST="${ROOT_DIR}/Packaging/Info.plist"
RELEASE_ROOT="${1:-${ROOT_DIR}/build/release}"
ACCOUNT="${GAUGELET_SPARKLE_KEY_ACCOUNT:-Gaugelet}"
WORK_ROOT=""

fail() {
    print -u2 -- "error: $*"
    exit 1
}

[[ -d "${RELEASE_ROOT}" ]] || fail "release directory not found: ${RELEASE_ROOT}"
RELEASE_ROOT="${RELEASE_ROOT:A}"
[[ "${RELEASE_ROOT}" != "/" && "${RELEASE_ROOT}" != "${ROOT_DIR}" ]] \
    || fail "refusing unsafe release directory: ${RELEASE_ROOT}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
DMG="${RELEASE_ROOT}/Gaugelet.dmg"
EXPECTED_URL="https://github.com/lammworks/Gaugelet/releases/download/v${VERSION}/Gaugelet.dmg"

for asset in Gaugelet.dmg Gaugelet.dmg.sha256 Gaugelet.app.dSYM.zip build-evidence.txt release-evidence.txt; do
    [[ -s "${RELEASE_ROOT}/${asset}" ]] || fail "missing release asset: ${asset}"
done
[[ -z "$(git -C "${ROOT_DIR}" status --porcelain --untracked-files=normal)" ]] \
    || fail "Sparkle finalization requires a clean source checkout"
ARTIFACT_KIND="$(/usr/bin/awk -F': ' '$1 == "Artifact kind" { print $2; exit }' \
    "${RELEASE_ROOT}/build-evidence.txt")"
SOURCE_COMMIT="$(/usr/bin/awk -F': ' '$1 == "Source commit" { print $2; exit }' \
    "${RELEASE_ROOT}/build-evidence.txt")"
SOURCE_DIRTY="$(/usr/bin/awk -F': ' '$1 == "Source tree dirty" { print $2; exit }' \
    "${RELEASE_ROOT}/build-evidence.txt")"
CURRENT_COMMIT="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
[[ ${#SOURCE_COMMIT} == 40 ]] \
    && print -r -- "${SOURCE_COMMIT}" | /usr/bin/grep -Eq '^[0-9a-f]{40}$' \
    || fail "build evidence contains an invalid source commit"
[[ "${SOURCE_COMMIT}" == "${CURRENT_COMMIT}" ]] \
    || fail "release assets came from ${SOURCE_COMMIT}, but the finalizer checkout is ${CURRENT_COMMIT}"
[[ "${SOURCE_DIRTY}" == "no" ]] \
    || fail "release assets were built from a dirty source tree"
case "${ARTIFACT_KIND}" in
    community-release)
        EXPECT_DEVELOPER_ID=0
        ;;
    'dormant Developer ID/notarized')
        EXPECT_DEVELOPER_ID=1
        ;;
    *)
        fail "unsupported release artifact kind: ${ARTIFACT_KIND:-missing}"
        ;;
esac
"${SCRIPT_DIR}/verify-sparkle-key-gates.sh"
GAUGELET_EXPECT_DEVELOPER_ID="${EXPECT_DEVELOPER_ID}" \
    "${SCRIPT_DIR}/verify-release.sh" "${RELEASE_ROOT}"

GENERATE_APPCAST="$("${SCRIPT_DIR}/sparkle-tool-path.sh" generate_appcast)"
SIGN_UPDATE="$("${SCRIPT_DIR}/sparkle-tool-path.sh" sign_update)"
WORK_ROOT="$(/usr/bin/mktemp -d "${RELEASE_ROOT}/.sparkle-finalize.XXXXXX")"
cleanup() {
    [[ -n "${WORK_ROOT}" && -d "${WORK_ROOT}" ]] && /bin/rm -rf "${WORK_ROOT}"
}
trap cleanup EXIT INT TERM

/usr/bin/ditto --noqtn "${DMG}" "${WORK_ROOT}/Gaugelet.dmg"
"${GENERATE_APPCAST}" \
    --account "${ACCOUNT}" \
    --maximum-deltas 0 \
    --maximum-versions 1 \
    --download-url-prefix "https://github.com/lammworks/Gaugelet/releases/download/v${VERSION}/" \
    --link 'https://github.com/lammworks/Gaugelet' \
    -o "${WORK_ROOT}/appcast.xml" \
    "${WORK_ROOT}"

[[ -s "${WORK_ROOT}/appcast.xml" ]] || fail "generate_appcast did not create appcast.xml"
if /usr/bin/find "${WORK_ROOT}" -type f -name '*.delta' -print | /usr/bin/grep -q .; then
    fail "delta updates were generated even though Gaugelet 1.0 is full-DMG only"
fi
/usr/bin/xmllint --noout "${WORK_ROOT}/appcast.xml"
"${SCRIPT_DIR}/verify-appcast.py" \
    "${WORK_ROOT}/appcast.xml" \
    --version "${VERSION}" \
    --build "${BUILD}" \
    --url "${EXPECTED_URL}" \
    --archive "${DMG}"
"${SIGN_UPDATE}" --account "${ACCOUNT}" --verify "${WORK_ROOT}/appcast.xml"
ARCHIVE_SIGNATURE="$("${SCRIPT_DIR}/verify-appcast.py" \
    "${WORK_ROOT}/appcast.xml" \
    --version "${VERSION}" \
    --build "${BUILD}" \
    --url "${EXPECTED_URL}" \
    --archive "${DMG}" \
    --print-archive-signature)"
"${SIGN_UPDATE}" --account "${ACCOUNT}" --verify "${DMG}" "${ARCHIVE_SIGNATURE}"

APPCAST_TEMP="${RELEASE_ROOT}/.appcast.xml.tmp.$$"
/usr/bin/install -m 644 "${WORK_ROOT}/appcast.xml" "${APPCAST_TEMP}"
/bin/mv -f "${APPCAST_TEMP}" "${RELEASE_ROOT}/appcast.xml"
APPCAST_SHA256="$(/usr/bin/shasum -a 256 "${RELEASE_ROOT}/appcast.xml" | /usr/bin/awk '{ print $1 }')"
DMG_SHA256="$(/usr/bin/awk '{ print $1 }' "${RELEASE_ROOT}/Gaugelet.dmg.sha256")"
{
    print -- "Gaugelet Sparkle release evidence"
    print -- "Version: ${VERSION}"
    print -- "Build: ${BUILD}"
    print -- "Keychain account: ${ACCOUNT}"
    print -- "Public key: matched committed SUPublicEDKey"
    print -- "Encrypted backups: two external files verified as release gates"
    print -- "Update format: full DMG only; deltas disabled"
    print -- "Enclosure URL: ${EXPECTED_URL}"
    print -- "DMG SHA-256: ${DMG_SHA256}"
    print -- "Appcast SHA-256: ${APPCAST_SHA256}"
    print -- "Appcast feed signature: verified with Sparkle sign_update"
    print -- "DMG EdDSA signature: verified with Sparkle sign_update"
} > "${RELEASE_ROOT}/sparkle-evidence.txt"

GAUGELET_EXPECT_DEVELOPER_ID="${EXPECT_DEVELOPER_ID}" \
    "${SCRIPT_DIR}/verify-release.sh" --require-appcast "${RELEASE_ROOT}"
print -- "Sparkle release finalized locally: ${RELEASE_ROOT}/appcast.xml"
print -- "No GitHub release or public asset was created or modified."
