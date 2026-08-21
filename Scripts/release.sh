#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
RELEASE_ROOT="${GAUGELET_RELEASE_ROOT:-${ROOT_DIR}/build/release}"

fail() {
    print -u2 -- "error: $*"
    exit 1
}

[[ -z "${GAUGELET_SIGNING_IDENTITY:-}" ]] \
    || fail "community release must remain ad-hoc; use Scripts/release-notarized.sh for Developer ID"
[[ -z "$(git -C "${ROOT_DIR}" status --porcelain --untracked-files=normal)" ]] \
    || fail "community release requires a clean source tree"
"${SCRIPT_DIR}/verify-sparkle-key-gates.sh" --configuration-only

GAUGELET_ARTIFACT_KIND=community-release \
GAUGELET_CANDIDATE_ROOT="${RELEASE_ROOT}" \
GAUGELET_REQUIRE_ASSET_CATALOG=1 \
    "${SCRIPT_DIR}/build-candidate.sh"

print -- "Unsigned-feed community assets are ready in ${RELEASE_ROOT}."
print -- "Download these exact CI-built bytes, then finalize locally with:"
print -- "  GAUGELET_SPARKLE_BACKUP_1=/absolute/backup-one.age \\\"
print -- "  GAUGELET_SPARKLE_BACKUP_2=/absolute/backup-two.age \\\"
print -- "  Scripts/finalize-sparkle-release.sh ${RELEASE_ROOT}"
print -- "No release was published."
