#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
ACCOUNT="${GAUGELET_SPARKLE_KEY_ACCOUNT:-Gaugelet}"
BACKUP="${1:-}"
WORK_ROOT=""

fail() {
    print -u2 -- "error: $*"
    exit 1
}

cleanup() {
    if [[ -n "${WORK_ROOT}" && -d "${WORK_ROOT}" ]]; then
        /bin/rm -rf -- "${WORK_ROOT}"
    fi
    return 0
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

[[ $# == 1 ]] \
    || fail "usage: test-sparkle-key-recovery.sh /absolute/Gaugelet-Sparkle-Key.age"
[[ -t 0 && -t 1 ]] \
    || fail "run this owner-only recovery drill interactively in a private Terminal window"
[[ -z "${CI:-}" ]] || fail "the recovery drill must never run in CI"
[[ -n "${ACCOUNT}" ]] || fail "GAUGELET_SPARKLE_KEY_ACCOUNT must not be empty"
[[ "${BACKUP}" == /* ]] || fail "the backup must use an absolute path"
[[ -f "${BACKUP}" && -s "${BACKUP}" && ! -L "${BACKUP}" ]] \
    || fail "the backup must be a non-symlink, non-empty file"
BACKUP="${BACKUP:A}"
[[ "${BACKUP}" != "${ROOT_DIR}"/* ]] || fail "the backup must be outside this repository"
[[ "${BACKUP:l}" == *.age ]] || fail "the backup must use the .age extension"

BACKUP_HEADER="$(/usr/bin/head -n 1 "${BACKUP}")"
[[ "${BACKUP_HEADER}" == 'age-encryption.org/v1' \
    || "${BACKUP_HEADER}" == '-----BEGIN AGE ENCRYPTED FILE-----' ]] \
    || fail "the file does not have an age-encrypted header"

AGE_BIN="${GAUGELET_AGE_BIN:-$(command -v age || true)}"
[[ -n "${AGE_BIN}" && -x "${AGE_BIN}" ]] || fail "age is required"
SIGN_UPDATE="$("${SCRIPT_DIR}/sparkle-tool-path.sh" sign_update)"

"${SCRIPT_DIR}/verify-sparkle-key-gates.sh" --keychain-only

WORK_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gaugelet-sparkle-recovery.XXXXXX")"
/bin/chmod 700 "${WORK_ROOT}"
umask 077

PRIVATE_KEY="${WORK_ROOT}/Gaugelet-Sparkle-Private-Key"
PROBE_FILE="${WORK_ROOT}/recovery-probe"
ERROR_LOG="${WORK_ROOT}/tool-error.log"
/usr/bin/touch "${PROBE_FILE}"

print -- "age will now ask for the backup passphrase locally. Nothing secret is printed or retained."
if ! "${AGE_BIN}" --decrypt -o "${PRIVATE_KEY}" "${BACKUP}"; then
    fail "the encrypted backup could not be decrypted"
fi
[[ -s "${PRIVATE_KEY}" && ! -L "${PRIVATE_KEY}" ]] \
    || fail "the decrypted backup did not produce private-key material"
/bin/chmod 600 "${PRIVATE_KEY}"

if ! SIGNATURE="$("${SIGN_UPDATE}" --ed-key-file "${PRIVATE_KEY}" -p "${PROBE_FILE}" 2>"${ERROR_LOG}")"; then
    fail "the recovered key could not sign the throwaway probe"
fi
[[ -n "${SIGNATURE}" ]] || fail "Sparkle returned an empty throwaway signature"

if ! "${SIGN_UPDATE}" --verify --account "${ACCOUNT}" \
    "${PROBE_FILE}" "${SIGNATURE}" >/dev/null 2>"${ERROR_LOG}"; then
    fail "the recovered key does not match the Keychain key trusted by Gaugelet"
fi

print -- "Sparkle recovery drill passed: the encrypted backup decrypted and signed a throwaway probe accepted by Gaugelet's trusted key"
print -- "The temporary plaintext key and probe are removed automatically when this script exits"
