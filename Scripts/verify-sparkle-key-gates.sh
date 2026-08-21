#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
INFO_PLIST="${ROOT_DIR}/Packaging/Info.plist"
ACCOUNT="${GAUGELET_SPARKLE_KEY_ACCOUNT:-Gaugelet}"
BACKUP_ONE="${GAUGELET_SPARKLE_BACKUP_1:-}"
BACKUP_TWO="${GAUGELET_SPARKLE_BACKUP_2:-}"
MODE="full"

fail() {
    print -u2 -- "error: $*"
    exit 1
}

set_mode() {
    local requested_mode="$1"
    [[ "${MODE}" == "full" ]] \
        || fail "choose only one verification mode"
    MODE="${requested_mode}"
}

while (( $# )); do
    case "$1" in
        --configuration-only)
            set_mode "configuration"
            ;;
        --keychain-only)
            set_mode "keychain"
            ;;
        --plist)
            shift
            [[ -n "${1:-}" ]] || fail "--plist requires a path"
            INFO_PLIST="$1"
            ;;
        *)
            fail "usage: verify-sparkle-key-gates.sh [--configuration-only|--keychain-only] [--plist /path/to/Info.plist]"
            ;;
    esac
    shift
done

[[ -f "${INFO_PLIST}" ]] || fail "missing ${INFO_PLIST}"
INFO_PLIST="${INFO_PLIST:A}"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${INFO_PLIST}" 2>/dev/null || true)"
[[ -n "${PUBLIC_KEY}" ]] || fail "SUPublicEDKey is missing"
[[ "${PUBLIC_KEY}" != *RELEASE_BLOCKED* && "${PUBLIC_KEY}" != *PLACEHOLDER* ]] \
    || fail "SUPublicEDKey is still a release-blocking placeholder"

PUBLIC_KEY_FINGERPRINT="$(/usr/bin/python3 - "${PUBLIC_KEY}" <<'PY'
import base64
import binascii
import hashlib
import sys

try:
    decoded = base64.b64decode(sys.argv[1], validate=True)
except (binascii.Error, ValueError) as error:
    raise SystemExit(f"error: SUPublicEDKey is not valid base64: {error}")
if len(decoded) != 32:
    raise SystemExit(f"error: SUPublicEDKey decodes to {len(decoded)} bytes, expected 32")
print(hashlib.sha256(decoded).hexdigest())
PY
)"

if [[ "${MODE}" == "configuration" ]]; then
    print -- "Sparkle public-key configuration gate passed (SHA-256 ${PUBLIC_KEY_FINGERPRINT})"
    exit 0
fi

[[ -n "${ACCOUNT}" ]] || fail "GAUGELET_SPARKLE_KEY_ACCOUNT must not be empty"
/usr/bin/security find-generic-password \
    -s 'https://sparkle-project.org' \
    -a "${ACCOUNT}" >/dev/null 2>&1 \
    || fail "no Sparkle private key exists in Keychain account ${ACCOUNT}; this verifier never generates one"

GENERATE_KEYS="$("${SCRIPT_DIR}/sparkle-tool-path.sh" generate_keys)"
KEYCHAIN_PUBLIC_KEY="$("${GENERATE_KEYS}" --account "${ACCOUNT}" -p)"
[[ "${KEYCHAIN_PUBLIC_KEY}" == "${PUBLIC_KEY}" ]] \
    || fail "Keychain account ${ACCOUNT} does not match the committed SUPublicEDKey"

if [[ "${MODE}" == "keychain" ]]; then
    print -- "Sparkle Keychain/public-key continuity gate passed (SHA-256 ${PUBLIC_KEY_FINGERPRINT})"
    exit 0
fi

check_backup() {
    local label="$1"
    local backup="$2"
    local permissions
    local backup_header
    local hard_link_count
    local git_root
    [[ -n "${backup}" ]] || fail "${label} path is required"
    [[ "${backup}" == /* ]] || fail "${label} must use an absolute path"
    [[ -f "${backup}" && -s "${backup}" && ! -L "${backup}" ]] \
        || fail "${label} must be a non-symlink, non-empty file: ${backup}"
    backup="${backup:A}"
    [[ "${backup}" != "${ROOT_DIR}"/* ]] || fail "${label} must not be stored in the Gaugelet repository"
    [[ "${backup:l}" == *.age ]] \
        || fail "${label} must be an age-encrypted backup with the .age extension"
    backup_header="$(/usr/bin/head -n 1 "${backup}")"
    [[ "${backup_header}" == 'age-encryption.org/v1' \
        || "${backup_header}" == '-----BEGIN AGE ENCRYPTED FILE-----' ]] \
        || fail "${label} does not have an age-encrypted file header"
    permissions="$(/usr/bin/stat -f '%Lp' "${backup}")"
    [[ "${permissions}" == "400" || "${permissions}" == "600" ]] \
        || fail "${label} must have mode 400 or 600 (current mode ${permissions})"
    hard_link_count="$(/usr/bin/stat -f '%l' "${backup}")"
    (( hard_link_count == 1 )) \
        || fail "${label} must not be a hard-linked backup"
    git_root="$(git -C "${backup:h}" rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -z "${git_root}" ]] \
        || fail "${label} must not be stored inside any Git work tree"
    print -- "${backup}"
}

BACKUP_ONE_CANONICAL="$(check_backup 'GAUGELET_SPARKLE_BACKUP_1' "${BACKUP_ONE}")"
BACKUP_TWO_CANONICAL="$(check_backup 'GAUGELET_SPARKLE_BACKUP_2' "${BACKUP_TWO}")"
[[ "${BACKUP_ONE_CANONICAL}" != "${BACKUP_TWO_CANONICAL}" ]] \
    || fail "the two encrypted Sparkle backups must be different files"
BACKUP_ONE_ID="$(/usr/bin/stat -f '%d:%i' "${BACKUP_ONE_CANONICAL}")"
BACKUP_TWO_ID="$(/usr/bin/stat -f '%d:%i' "${BACKUP_TWO_CANONICAL}")"
[[ "${BACKUP_ONE_ID}" != "${BACKUP_TWO_ID}" ]] \
    || fail "the two encrypted Sparkle backups resolve to the same underlying file"

if [[ "${BACKUP_ONE_ID%%:*}" == "${BACKUP_TWO_ID%%:*}" ]]; then
    print -u2 -- "warning: both backup containers are on the same local filesystem; confirm separate storage control manually"
fi

print -- "Sparkle non-secret custody checks passed (SHA-256 ${PUBLIC_KEY_FINGERPRINT}): Keychain continuity and two distinct encrypted backup containers"
print -- "Manual gate remains: record independent storage control and a successful recovery drill; this verifier never decrypts a backup"
