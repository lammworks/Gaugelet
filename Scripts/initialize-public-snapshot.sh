#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
SNAPSHOT="${1:-}"

fail() {
    print -u2 -- "error: $*"
    exit 1
}

[[ -n "${SNAPSHOT}" && "${SNAPSHOT}" == /* && -d "${SNAPSHOT}" ]] \
    || fail "usage: initialize-public-snapshot.sh /absolute/public-snapshot"
SNAPSHOT="${SNAPSHOT:A}"
[[ "${SNAPSHOT}" != "/" && "${SNAPSHOT}" != "${ROOT_DIR}" ]] \
    || fail "refusing unsafe snapshot directory"
[[ ! -e "${SNAPSHOT}/.git" ]] \
    || fail "snapshot already contains .git; this script never rewrites history"

GAUGELET_REQUIRE_EXTERNAL_SCANNERS=1 \
    "${SCRIPT_DIR}/scan-public-export.sh" "${SNAPSHOT}"
"${SCRIPT_DIR}/hash-manifest.py" --verify "${SNAPSHOT}"

/usr/bin/git -C "${SNAPSHOT}" init -b main
/usr/bin/git -C "${SNAPSHOT}" config user.name LammWorks
/usr/bin/git -C "${SNAPSHOT}" config user.email lammworks@users.noreply.github.com
/usr/bin/git -C "${SNAPSHOT}" config commit.gpgsign false

STAGE_LIST="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/gaugelet-public-stage.XXXXXX")"
cleanup() {
    [[ -f "${STAGE_LIST}" ]] && /bin/rm -f "${STAGE_LIST}"
}
trap cleanup EXIT INT TERM
(
    cd "${SNAPSHOT}"
    /usr/bin/find . -path './.git' -prune -o -type f -print0 > "${STAGE_LIST}"
    /usr/bin/xargs -0 /usr/bin/git add -- < "${STAGE_LIST}"
)
/usr/bin/git -C "${SNAPSHOT}" commit --no-gpg-sign -m 'Initial public release'

[[ "$(/usr/bin/git -C "${SNAPSHOT}" rev-list --count HEAD)" == "1" ]] \
    || fail "public snapshot must have exactly one root commit"
[[ -z "$(/usr/bin/git -C "${SNAPSHOT}" remote)" ]] \
    || fail "public snapshot unexpectedly has a Git remote"
[[ -z "$(/usr/bin/git -C "${SNAPSHOT}" status --porcelain)" ]] \
    || fail "public snapshot is not clean after its root commit"

print -- "Unrelated one-root-commit repository prepared locally: ${SNAPSHOT}"
print -- "Commit: $(/usr/bin/git -C "${SNAPSHOT}" rev-parse HEAD)"
print -- "Identity: LammWorks <lammworks@users.noreply.github.com>"
print -- "No remote or public GitHub repository was created."
