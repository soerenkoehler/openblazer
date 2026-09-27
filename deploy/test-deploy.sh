#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin" "$TEST_DIR/project/deploy" "$TEST_DIR/project/dist" "$TEST_DIR/project/game" "$TEST_DIR/project/msix" "$TEST_DIR/project/deploy/release-notes"
cp "$ROOT/deploy/deploy.sh" "$ROOT/deploy/update-appmanifest.xslt" "$TEST_DIR/project/deploy/"
cp "$ROOT/msix/AppxManifest.xml" "$TEST_DIR/project/msix/"
cp "$ROOT/openblazer.code-workspace" "$TEST_DIR/project/"
printf 'config/name="openblazer"\n' > "$TEST_DIR/project/game/project.godot"
printf '#!/bin/bash\n[[ ${TEST_EXPORT_FAIL:-} != 1 ]] || exit 1\nprintf "export" > "${@: -1}"\n' > "$TEST_DIR/project/godot"

printf '%s\n' '#!/bin/bash' 'printf "Version=\"%s\"\n" "$3"' > "$TEST_DIR/bin/xsltproc"
printf '%s\n' '#!/bin/bash' \
    'while [[ $# -gt 0 ]]; do' \
    '    if [[ $1 == -v ]]; then STAGE=${2%:/workspace}; break; fi' \
    '    shift' \
    'done' \
    '[[ -s $STAGE/msix/openblazer.exe && $(<"$STAGE/msix/AppxManifest.xml") == *"Version=\"$EXPECTED_VERSION\""* ]] || exit 1' \
    'printf "package" > "$STAGE/openblazer.msix"' > "$TEST_DIR/bin/docker"
printf '%s\n' '#!/bin/bash' \
    'if [[ $1 == release && $2 == view ]]; then exit 1; fi' \
    'if [[ $1 == release && $2 == upload ]]; then [[ -s ${@: -1} ]] || exit 1; fi' \
    'printf "gh:%s %s\n" "$1" "$2" >> "$TEST_LOG"' > "$TEST_DIR/bin/gh"
printf '%s\n' '#!/bin/bash' \
    '[[ $1 == fetch || $1 == tag ]] || exit 1' > "$TEST_DIR/bin/git"
printf '%s\n' '#!/bin/bash' \
    'printf "msstore:%s %s\n" "$1" "$2" >> "$TEST_LOG"' \
    'case "$1 $2" in' \
    '    "apps get") if [[ ${TEST_PENDING:-} == missing ]]; then printf "{\"Id\":\"test\"}\n"; else printf "{\"PendingApplicationSubmission\":%s}\n" "${TEST_PENDING:-null}"; fi ;;' \
    '    "submission get") if [[ ${TEST_MISSING_LOCALE:-} == 1 ]]; then printf "%s\n" '\''{"Listings":{"de-de":{"BaseListing":{"ReleaseNotes":"alt"}}},"Packages":[1]}'\''; else printf "%s\n" '\''{"Listings":{"en-us":{"BaseListing":{"ReleaseNotes":"old"}},"de-de":{"BaseListing":{"ReleaseNotes":"alt"}}},"Packages":[1]}'\''; fi ;;' \
    '    "submission updateMetadata") jq -e '\''(.Listings["en-us"].BaseListing.ReleaseNotes == "Release details") and (.Listings["de-de"].BaseListing.ReleaseNotes == "alt") and (.Packages == [1])'\'' <<< "$4" >/dev/null ;;' \
    'esac' > "$TEST_DIR/bin/msstore"
printf '%s\n' '#!/bin/bash' 'printf "DBUS_SESSION_BUS_ADDRESS=mock; export DBUS_SESSION_BUS_ADDRESS\n"' > "$TEST_DIR/bin/dbus-launch"
printf '%s\n' '#!/bin/bash' 'exit 0' > "$TEST_DIR/bin/gnome-keyring-daemon"
chmod +x "$TEST_DIR/project/godot" "$TEST_DIR/bin/"*

export PATH="$TEST_DIR/bin:$PATH" TEST_LOG="$TEST_DIR/calls"
export MSSTORE_STORE_ID=test MSSTORE_SELLER_ID=test MSSTORE_TENANT_ID=test MSSTORE_CLIENT_ID=test MSSTORE_CLIENT_SECRET=test
cd "$TEST_DIR/project"

for BAD_TAG in v1.2.3extra v0.1.0 v1.65536.0; do
    if GITHUB_REF_TYPE=tag GITHUB_REF_NAME="$BAD_TAG" ./deploy/deploy.sh package >/dev/null 2>&1; then
        printf 'accepted invalid tag: %s\n' "$BAD_TAG" >&2
        exit 1
    fi
done

export GITHUB_REF_TYPE=tag GITHUB_REF_NAME=v1.2.3 EXPECTED_VERSION=1.2.3.0
printf 'stale' > dist/openblazer.exe
printf 'keep' > dist/keep.txt
if TEST_EXPORT_FAIL=1 ./deploy/deploy.sh package >/dev/null 2>&1; then
    printf 'accepted failed Godot export\n' >&2
    exit 1
fi
[[ ! -e dist/openblazer.exe && ! -e dist/openblazer.msix && $(<dist/keep.txt) == keep ]]
./deploy/deploy.sh package
[[ $(<dist/openblazer.exe) == export && $(<dist/openblazer.msix) == package && $(<dist/keep.txt) == keep ]]
cmp msix/AppxManifest.xml "$ROOT/msix/AppxManifest.xml"

if ./deploy/deploy.sh release >/dev/null 2>&1; then
    printf 'accepted missing release notes\n' >&2
    exit 1
fi
printf 'Release details\n' > deploy/release-notes/v1.2.3.en-us.txt
./deploy/deploy.sh release
mapfile -t CALLS < "$TEST_LOG"
[[ ${CALLS[*]} == *'msstore:apps get'*'msstore:publish '*'msstore:submission get'*'msstore:submission updateMetadata'*'msstore:submission publish'*'msstore:submission poll'* ]]

: > "$TEST_LOG"
if TEST_PENDING='{"Id":"existing"}' ./deploy/deploy.sh release >/dev/null 2>&1; then
    printf 'overwrote existing Store submission\n' >&2
    exit 1
fi
! grep -q 'msstore:publish' "$TEST_LOG"

: > "$TEST_LOG"
if TEST_PENDING=missing ./deploy/deploy.sh release >/dev/null 2>&1; then
    printf 'accepted unknown Store submission state\n' >&2
    exit 1
fi
! grep -q 'msstore:publish' "$TEST_LOG"

: > "$TEST_LOG"
if TEST_MISSING_LOCALE=1 ./deploy/deploy.sh release >/dev/null 2>&1; then
    printf 'accepted missing en-us listing\n' >&2
    exit 1
fi
! grep -q 'msstore:submission publish' "$TEST_LOG"

export GITHUB_REF_TYPE=branch GITHUB_REF_NAME=dev GITHUB_RUN_NUMBER=24 EXPECTED_VERSION=1.0.24.0
./deploy/deploy.sh package
if ./deploy/deploy.sh release >/dev/null 2>&1; then
    printf 'dev branch published a release\n' >&2
    exit 1
fi

: > "$TEST_LOG"
export GITHUB_REF_NAME=main GITHUB_SHA=0123456789abcdef
./deploy/deploy.sh release
grep -q 'gh:release create' "$TEST_LOG"
! grep -q 'msstore:' "$TEST_LOG"

printf 'deployment smoke tests passed\n'