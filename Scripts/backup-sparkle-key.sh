#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
ACCOUNT="${GAUGELET_SPARKLE_KEY_ACCOUNT:-Gaugelet}"
BACKUP_ONE="${1:-}"
BACKUP_TWO="${2:-}"
WORK_ROOT=""
PARTIAL_ONE=""
PARTIAL_TWO=""

fail() {
    print -u2 -- "error: $*"
    exit 1
}

cleanup() {
    if [[ -n "${PARTIAL_ONE}" && ( -f "${PARTIAL_ONE}" || -L "${PARTIAL_ONE}" ) ]]; then
        /bin/rm -f -- "${PARTIAL_ONE}"
    fi
    if [[ -n "${PARTIAL_TWO}" && ( -f "${PARTIAL_TWO}" || -L "${PARTIAL_TWO}" ) ]]; then
        /bin/rm -f -- "${PARTIAL_TWO}"
    fi
    if [[ -n "${WORK_ROOT}" && -d "${WORK_ROOT}" ]]; then
        /bin/rm -rf -- "${WORK_ROOT}"
    fi
    return 0
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

[[ $# == 2 ]] \
    || fail "usage: backup-sparkle-key.sh /absolute/backup-one.age /absolute/backup-two.age"
[[ -n "${ACCOUNT}" ]] || fail "GAUGELET_SPARKLE_KEY_ACCOUNT must not be empty"

AGE_BIN="${GAUGELET_AGE_BIN:-$(command -v age || true)}"
[[ -n "${AGE_BIN}" && -x "${AGE_BIN}" ]] \
    || fail "age is required; install it with Homebrew, then rerun this script"

validate_destination() {
    local label="$1"
    local destination="$2"
    local parent

    [[ "${destination}" == /* ]] || fail "${label} must use an absolute path"
    [[ "${destination:l}" == *.age ]] || fail "${label} must end in .age"
    [[ ! -e "${destination}" && ! -L "${destination}" ]] \
        || fail "${label} already exists; this script never overwrites backups: ${destination}"
    parent="${destination:h}"
    [[ -d "${parent}" && ! -L "${parent}" ]] \
        || fail "${label} parent must be an existing non-symlink directory: ${parent}"
    parent="${parent:A}"
    destination="${parent}/${destination:t}"
    [[ "${destination}" != "${ROOT_DIR}"/* ]] \
        || fail "${label} must be outside the Gaugelet repository"
    print -r -- "${destination}"
}

BACKUP_ONE="$(validate_destination 'backup one' "${BACKUP_ONE}")"
BACKUP_TWO="$(validate_destination 'backup two' "${BACKUP_TWO}")"
[[ "${BACKUP_ONE}" != "${BACKUP_TWO}" ]] \
    || fail "the two encrypted backups must use different paths"

GENERATE_KEYS="$("${SCRIPT_DIR}/sparkle-tool-path.sh" generate_keys)"
WORK_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gaugelet-sparkle-backup.XXXXXX")"
/bin/chmod 700 "${WORK_ROOT}"
umask 077

PRIVATE_KEY="${WORK_ROOT}/Gaugelet-Sparkle-Private-Key"
ENCRYPTED_KEY="${WORK_ROOT}/Gaugelet-Sparkle-Private-Key.age"
PARTIAL_ONE="${BACKUP_ONE}.partial.$$"
PARTIAL_TWO="${BACKUP_TWO}.partial.$$"
[[ ! -e "${PARTIAL_ONE}" && ! -L "${PARTIAL_ONE}" ]] \
    || fail "temporary destination already exists: ${PARTIAL_ONE}"
[[ ! -e "${PARTIAL_TWO}" && ! -L "${PARTIAL_TWO}" ]] \
    || fail "temporary destination already exists: ${PARTIAL_TWO}"

print -- "Exporting the existing Sparkle key from Keychain account ${ACCOUNT}."
print -- "age will prompt locally for a passphrase. Store it separately from both backup files."
"${GENERATE_KEYS}" --account "${ACCOUNT}" -x "${PRIVATE_KEY}"
[[ -s "${PRIVATE_KEY}" && ! -L "${PRIVATE_KEY}" ]] \
    || fail "Sparkle did not export a private key"
/bin/chmod 600 "${PRIVATE_KEY}"

"${AGE_BIN}" -p -o "${ENCRYPTED_KEY}" "${PRIVATE_KEY}"
[[ -s "${ENCRYPTED_KEY}" && ! -L "${ENCRYPTED_KEY}" ]] \
    || fail "age did not create an encrypted backup"
/bin/chmod 600 "${ENCRYPTED_KEY}"

/usr/bin/install -m 600 "${ENCRYPTED_KEY}" "${PARTIAL_ONE}"
/usr/bin/install -m 600 "${ENCRYPTED_KEY}" "${PARTIAL_TWO}"
ENCRYPTED_SHA256="$(/usr/bin/shasum -a 256 "${ENCRYPTED_KEY}" | /usr/bin/awk '{ print $1 }')"
for partial in "${PARTIAL_ONE}" "${PARTIAL_TWO}"; do
    [[ "$(/usr/bin/shasum -a 256 "${partial}" | /usr/bin/awk '{ print $1 }')" == "${ENCRYPTED_SHA256}" ]] \
        || fail "encrypted backup copy failed hash verification: ${partial}"
done

/bin/mv "${PARTIAL_ONE}" "${BACKUP_ONE}"
PARTIAL_ONE=""
/bin/mv "${PARTIAL_TWO}" "${BACKUP_TWO}"
PARTIAL_TWO=""
/bin/rm -f -- "${PRIVATE_KEY}"

GAUGELET_SPARKLE_KEY_ACCOUNT="${ACCOUNT}" \
GAUGELET_SPARKLE_BACKUP_1="${BACKUP_ONE}" \
GAUGELET_SPARKLE_BACKUP_2="${BACKUP_TWO}" \
    "${SCRIPT_DIR}/verify-sparkle-key-gates.sh"

print -- "Encrypted Sparkle backups created and verified:"
print -- "  ${BACKUP_ONE}"
print -- "  ${BACKUP_TWO}"
print -- "Next gate: restore one backup in a disposable macOS user or temporary test Keychain and record the result."
