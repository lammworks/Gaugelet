#!/bin/zsh

set -euo pipefail

FRAMEWORK="${1:-}"
REFERENCE_FRAMEWORK="${2:-}"

fail() {
    print -u2 -- "error: $*"
    exit 1
}

[[ -n "${FRAMEWORK}" && -d "${FRAMEWORK}" ]] \
    || fail "usage: verify-sparkle-framework.sh /path/to/Sparkle.framework [/reference/Sparkle.framework]"
FRAMEWORK="${FRAMEWORK:A}"
[[ "${FRAMEWORK:t}" == "Sparkle.framework" ]] || fail "not a Sparkle.framework: ${FRAMEWORK}"

for link in Versions/Current Sparkle Resources; do
    [[ -L "${FRAMEWORK}/${link}" ]] || fail "Sparkle framework is missing symlink ${link}"
done

while IFS= read -r symlink; do
    target="$(/usr/bin/readlink "${symlink}")"
    [[ -n "${target}" ]] || fail "empty framework symlink: ${symlink}"
    [[ "${target}" != /* ]] || fail "absolute framework symlink is not allowed: ${symlink} -> ${target}"
done < <(/usr/bin/find "${FRAMEWORK}" -type l -print | /usr/bin/sort)

INFO_PLIST="${FRAMEWORK}/Resources/Info.plist"
[[ -f "${INFO_PLIST}" ]] || fail "Sparkle framework is missing Resources/Info.plist"
SPARKLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
[[ "${SPARKLE_VERSION}" == "2.9.5" ]] \
    || fail "embedded Sparkle version is ${SPARKLE_VERSION}, expected 2.9.5"

MACHO_COUNT=0
while IFS= read -r -d '' item; do
    if /usr/bin/file -b "${item}" | /usr/bin/grep -F 'Mach-O' >/dev/null; then
        MACHO_COUNT=$(( MACHO_COUNT + 1 ))
        architectures="$(/usr/bin/lipo -archs "${item}")"
        [[ " ${architectures} " == *" arm64 "* ]] \
            || fail "vendor Sparkle binary is missing arm64: ${item}"
        [[ " ${architectures} " == *" x86_64 "* ]] \
            || fail "vendor Sparkle binary was thinned and is missing x86_64: ${item}"
    fi
done < <(/usr/bin/find "${FRAMEWORK}" -type f -print0)
(( MACHO_COUNT >= 4 )) || fail "found only ${MACHO_COUNT} Mach-O files in Sparkle.framework"

if [[ -n "${REFERENCE_FRAMEWORK}" ]]; then
    [[ -d "${REFERENCE_FRAMEWORK}" ]] || fail "reference framework not found: ${REFERENCE_FRAMEWORK}"
    REFERENCE_FRAMEWORK="${REFERENCE_FRAMEWORK:A}"
    TEMP_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gaugelet-symlinks.XXXXXX")"
    cleanup() {
        [[ -d "${TEMP_ROOT}" ]] && /bin/rm -rf "${TEMP_ROOT}"
    }
    trap cleanup EXIT INT TERM
    for pair in "reference:${REFERENCE_FRAMEWORK}" "packaged:${FRAMEWORK}"; do
        label="${pair%%:*}"
        root="${pair#*:}"
        while IFS= read -r symlink; do
            relative="${symlink#${root}/}"
            print -- "${relative} -> $(/usr/bin/readlink "${symlink}")"
        done < <(/usr/bin/find "${root}" -type l -print | /usr/bin/sort) \
            > "${TEMP_ROOT}/${label}.txt"
    done
    /usr/bin/cmp "${TEMP_ROOT}/reference.txt" "${TEMP_ROOT}/packaged.txt" \
        || fail "packaged Sparkle framework symlink topology differs from the vendor artifact"
fi

if [[ "${GAUGELET_VERIFY_SPARKLE_SIGNATURES:-0}" == "1" ]]; then
    /usr/bin/codesign --verify --deep --strict --verbose=2 "${FRAMEWORK}"
fi

print -- "Sparkle framework verified: ${SPARKLE_VERSION}, ${MACHO_COUNT} universal Mach-O files, symlinks preserved"
