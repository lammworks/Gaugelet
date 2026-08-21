#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
ALLOWLIST="${SCRIPT_DIR}/public-export-allowlist.txt"
DESTINATION="${1:-}"
CREATED_DESTINATION=0
FILE_LIST=""

fail() {
    print -u2 -- "error: $*"
    exit 1
}

[[ -n "${DESTINATION}" ]] || fail "usage: prepare-public-export.sh /absolute/new/snapshot-directory"
[[ "${DESTINATION}" == /* ]] || fail "public snapshot destination must be absolute"
[[ ! -e "${DESTINATION}" && ! -L "${DESTINATION}" ]] \
    || fail "destination already exists; this script never deletes or overwrites it"
[[ -f "${ALLOWLIST}" ]] || fail "missing public export allowlist"
[[ -z "$(git -C "${ROOT_DIR}" status --porcelain --untracked-files=normal)" ]] \
    || fail "public export requires a clean source tree"

DESTINATION_PARENT="${DESTINATION:h}"
if [[ ! -d "${DESTINATION_PARENT}" ]]; then
    /usr/bin/install -d "${DESTINATION_PARENT}"
fi
[[ -d "${DESTINATION_PARENT}" && ! -L "${DESTINATION_PARENT}" ]] \
    || fail "snapshot parent must be a real directory: ${DESTINATION_PARENT}"
DESTINATION_PARENT="${DESTINATION_PARENT:A}"
DESTINATION="${DESTINATION_PARENT}/${DESTINATION:t}"
[[ "${DESTINATION}" != "/" && "${DESTINATION}" != "${ROOT_DIR}" ]] \
    || fail "refusing unsafe public snapshot destination"

/usr/bin/install -d -m 700 "${DESTINATION}"
CREATED_DESTINATION=1
cleanup_on_failure() {
    exit_code=$?
    [[ -n "${FILE_LIST}" && -f "${FILE_LIST}" ]] && /bin/rm -f "${FILE_LIST}"
    if (( exit_code != 0 && CREATED_DESTINATION )); then
        print -u2 -- "Public export failed. Partial snapshot was retained for inspection: ${DESTINATION}"
    fi
    return ${exit_code}
}
trap cleanup_on_failure EXIT

FILE_LIST="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/gaugelet-public-files.XXXXXX")"
"${SCRIPT_DIR}/select-public-files.py" \
    --root "${ROOT_DIR}" \
    --allowlist "${ALLOWLIST}" \
    --nul > "${FILE_LIST}"

COPIED=0
while IFS= read -r -d '' relative; do
    source_path="${ROOT_DIR}/${relative}"
    destination_path="${DESTINATION}/${relative}"
    [[ -f "${source_path}" && ! -L "${source_path}" ]] \
        || fail "allowlisted source must be a regular non-symlink file: ${relative}"
    /usr/bin/install -d "${destination_path:h}"
    /usr/bin/ditto --noqtn --noextattr "${source_path}" "${destination_path}"
    [[ "$(/usr/bin/shasum -a 256 "${source_path}" | /usr/bin/awk '{ print $1 }')" \
        == "$(/usr/bin/shasum -a 256 "${destination_path}" | /usr/bin/awk '{ print $1 }')" ]] \
        || fail "copy hash mismatch: ${relative}"
    COPIED=$(( COPIED + 1 ))
done < "${FILE_LIST}"
/bin/rm -f "${FILE_LIST}"
FILE_LIST=""
(( COPIED > 0 )) || fail "public allowlist selected no files"
/bin/chmod 700 "${DESTINATION}"

GAUGELET_REQUIRE_EXTERNAL_SCANNERS=1 \
    "${SCRIPT_DIR}/scan-public-export.sh" "${DESTINATION}"
"${SCRIPT_DIR}/hash-manifest.py" "${DESTINATION}"
"${SCRIPT_DIR}/hash-manifest.py" --verify "${DESTINATION}"

trap - EXIT
print -- "Clean public snapshot prepared: ${DESTINATION}"
print -- "Files copied: ${COPIED}"
print -- "No Git repository, remote, GitHub repository, release, or public resource was created."
print -- "After independent visual/PII review, create the unrelated one-commit local repository with:"
print -- "  Scripts/initialize-public-snapshot.sh ${DESTINATION}"
