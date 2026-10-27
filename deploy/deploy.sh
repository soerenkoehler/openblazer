#!/bin/bash
set -euo pipefail

main() {
    THIS_SCRIPT=$(realpath -e "$0")
    DIR_THIS_SCRIPT=$(dirname "$THIS_SCRIPT")
    DIR_GAME="$PWD/game"
    DIR_DIST="$PWD/dist"
    DIR_MSIX="$PWD/msix"

    [[ -d $DIR_GAME && -d $DIR_DIST && -d $DIR_MSIX ]] || { printf "missing game, dist or msix directory\n" >&2; exit 1; }

    PROJECT=$(
        grep -E '^config/name=".+"' "$DIR_GAME/project.godot" \
        | cut -d'=' -f2 \
        | tr -d '"'
    )
    [[ -n $PROJECT ]] || { printf "missing Godot project name\n" >&2; exit 1; }
    GODOT_VERSION=4.6.2-stable

    initialize_workspace "${1:-}"

    case $1 in

    install)
        install_system_dependencies
        install_godot
    ;;

    install-store)
        install_store_dependencies
    ;;

    package)
        rm -f -- "$DIR_DIST/$PROJECT.exe" "$DIR_DIST/$PROJECT.x64" "$DIR_DIST/$PROJECT.msix"
        package
        package_msix
        if [[ -n ${GITHUB_OUTPUT:-} ]]; then
            printf 'msix_version=%s\n' "$VERSION" >> "$GITHUB_OUTPUT"
        fi
    ;;

    release)
        release
    ;;

    *)
        printf "missing or wrong command: %s\n" "${1:-}" >&2
        exit 1
    ;;

    esac
}

initialize_workspace() {
    # check working dir
    if [[ ! -e "$PROJECT.code-workspace" ]]; then
        printf "not in project root\n"
        exit -1
    fi

    [[ ${1:-} == install || ${1:-} == install-store ]] && return

    if [[ ${GITHUB_REF_TYPE:-} == tag ]]; then
        if ! parse_version_tag "${GITHUB_REF_NAME:-}"; then
            printf "invalid release tag: %s\n" "${GITHUB_REF_NAME:-}" >&2
            exit 1
        fi
        local MAJOR=$TAG_MAJOR MINOR=$TAG_MINOR PATCH=$TAG_PATCH TAGS TAG_COUNT=0 CANDIDATE
        validate_msix_components "$MAJOR" "$MINOR" "$PATCH"
        if ! TAGS=$(git tag --list); then
            printf "failed to enumerate Git tags\n" >&2
            exit 1
        fi
        while IFS= read -r CANDIDATE || [[ -n $CANDIDATE ]]; do
            if parse_version_tag "$CANDIDATE" && [[ $TAG_VERSION == "$MAJOR.$MINOR.$PATCH" ]]; then
                TAG_COUNT=$((TAG_COUNT + 1))
            fi
        done <<< "$TAGS"
        (( TAG_COUNT == 1 )) || {
            printf "version tag is not unique: %s\n" "$MAJOR.$MINOR.$PATCH" >&2
            exit 1
        }
        RELEASE=$GITHUB_REF_NAME
        RELEASE_TITLE="v$MAJOR.$MINOR.$PATCH"
        VERSION="$MAJOR.$MINOR.$PATCH.0"
    elif [[ ${GITHUB_REF_TYPE:-} == branch && -n ${GITHUB_REF_NAME:-} ]]; then
        local BRANCH_TAGS REMOTE_BRANCHES CANDIDATE SELECTED_VERSION= SELECTED_COUNT=0
        local BRANCH_NAME BRANCH_SUFFIX OTHER_SUFFIX MAJOR MINOR PATCH

        BRANCH_SUFFIX=$(normalize_branch_name "$GITHUB_REF_NAME")
        if ! REMOTE_BRANCHES=$(git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin); then
            printf "failed to enumerate remote branches\n" >&2
            exit 1
        fi
        while IFS= read -r BRANCH_NAME || [[ -n $BRANCH_NAME ]]; do
            [[ -n $BRANCH_NAME && $BRANCH_NAME != HEAD && $BRANCH_NAME != "$GITHUB_REF_NAME" ]] || continue
            OTHER_SUFFIX=$(normalize_branch_name "$BRANCH_NAME")
            if [[ $OTHER_SUFFIX == "$BRANCH_SUFFIX" ]]; then
                printf "branch names normalize to the same nightly identifier: %s and %s\n" "$GITHUB_REF_NAME" "$BRANCH_NAME" >&2
                exit 1
            fi
        done <<< "$REMOTE_BRANCHES"

        if ! BRANCH_TAGS=$(git tag --list); then
            printf "failed to enumerate Git tags\n" >&2
            exit 1
        fi
        while IFS= read -r CANDIDATE || [[ -n $CANDIDATE ]]; do
            if parse_version_tag "$CANDIDATE"; then
                if [[ -z $SELECTED_VERSION ]] || version_is_greater "$TAG_VERSION" "$SELECTED_VERSION"; then
                    SELECTED_VERSION=$TAG_VERSION
                    SELECTED_COUNT=1
                elif [[ $TAG_VERSION == "$SELECTED_VERSION" ]]; then
                    SELECTED_COUNT=$((SELECTED_COUNT + 1))
                fi
            fi
        done <<< "$BRANCH_TAGS"

        if [[ -z $SELECTED_VERSION ]]; then
            MAJOR=1
            MINOR=0
            PATCH=0
        else
            (( SELECTED_COUNT == 1 )) || {
                printf "highest reference version is not unique: %s\n" "$SELECTED_VERSION" >&2
                exit 1
            }
            IFS=. read -r MAJOR MINOR PATCH <<< "$SELECTED_VERSION"
            validate_msix_components "$MAJOR" "$MINOR" "$PATCH"
            if (( 10#$PATCH == 65535 )); then
                printf "nightly patch version exceeds MSIX range: %s\n" "$PATCH" >&2
                exit 1
            fi
            PATCH=$((10#$PATCH + 1))
        fi
        NIGHTLY_RELEASE_TAG="nightly-$BRANCH_SUFFIX"
        RELEASE=$NIGHTLY_RELEASE_TAG
        RELEASE_TITLE="v$MAJOR.$MINOR.$PATCH-nightly-$BRANCH_SUFFIX"
        VERSION="$MAJOR.$MINOR.$PATCH.0"
    else
        printf "unsupported GitHub ref: %s %s\n" "${GITHUB_REF_TYPE:-}" "${GITHUB_REF_NAME:-}" >&2
        exit 1
    fi

    if [[ ${DEPLOY_EXPECTED_VERSION+x} == x && $VERSION != "$DEPLOY_EXPECTED_VERSION" ]]; then
        printf "resolved MSIX version %s differs from packaged version %s\n" "$VERSION" "$DEPLOY_EXPECTED_VERSION" >&2
        exit 1
    fi
}

parse_version_tag() {
    if [[ $1 =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-.+)?$ ]]; then
        TAG_MAJOR=${BASH_REMATCH[1]}
        TAG_MINOR=${BASH_REMATCH[2]}
        TAG_PATCH=${BASH_REMATCH[3]}
        TAG_VERSION="$TAG_MAJOR.$TAG_MINOR.$TAG_PATCH"
        return 0
    fi
    return 1
}

validate_msix_components() {
    local MAJOR=$1 MINOR=$2 PATCH=$3 PART
    for PART in "$MAJOR" "$MINOR" "$PATCH"; do
        if (( ${#PART} > 5 )) || (( 10#$PART > 65535 )); then
            printf "version component outside MSIX range: %s\n" "$PART" >&2
            exit 1
        fi
    done
    (( 10#$MAJOR > 0 )) || { printf "MSIX major version must be positive\n" >&2; exit 1; }
}

version_is_greater() {
    local LC_ALL=C LEFT_VERSION=$1 RIGHT_VERSION=$2 INDEX
    local -a LEFT_PARTS=() RIGHT_PARTS=()
    IFS=. read -r -a LEFT_PARTS <<< "$LEFT_VERSION"
    IFS=. read -r -a RIGHT_PARTS <<< "$RIGHT_VERSION"
    for INDEX in 0 1 2; do
        if (( ${#LEFT_PARTS[INDEX]} > ${#RIGHT_PARTS[INDEX]} )); then
            return 0
        elif (( ${#LEFT_PARTS[INDEX]} < ${#RIGHT_PARTS[INDEX]} )); then
            return 1
        elif [[ ${LEFT_PARTS[INDEX]} > ${RIGHT_PARTS[INDEX]} ]]; then
            return 0
        elif [[ ${LEFT_PARTS[INDEX]} < ${RIGHT_PARTS[INDEX]} ]]; then
            return 1
        fi
    done
    return 1
}

normalize_branch_name() {
    local NORMALIZED
    NORMALIZED=$(printf '%s' "$1" | sed 's/[^A-Za-z0-9-]/-/g')
    [[ -n $NORMALIZED ]] || { printf "branch name has no usable characters: %s\n" "$1" >&2; exit 1; }
    printf '%s' "$NORMALIZED"
}

install_system_dependencies() {
    sudo apt-get update
    sudo apt-get install -y xsltproc
}

install_store_dependencies() {
    sudo apt-get update
    sudo apt-get install -y dbus-x11 gnome-keyring libsecret-1-0
}

install_godot() {
    for FILE in linux.x86_64.zip export_templates.tpz
    do
        curl \
            --fail \
            --location \
            --remote-name \
            "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_${FILE}"
        unzip "Godot_v${GODOT_VERSION}_${FILE}"
    done

    TEMPLATE_DIR=~/.local/share/godot/export_templates/$(tr '-' '.' <<< "$GODOT_VERSION")/
    mkdir -p "$TEMPLATE_DIR"
    mv -v templates/* "$TEMPLATE_DIR"

    mv -v "./Godot_v${GODOT_VERSION}_linux.x86_64" ./godot
    chmod 700 ./godot
    ./godot --version
}

package() {
    ./godot --headless --path "$DIR_GAME" --export-release "Windows Desktop" "$DIR_DIST/$PROJECT.exe"
    ./godot --headless --path "$DIR_GAME" --export-release "Linux"           "$DIR_DIST/$PROJECT.x64"
    [[ -s "$DIR_DIST/$PROJECT.exe" && -s "$DIR_DIST/$PROJECT.x64" ]] || { printf "missing Godot export\n" >&2; exit 1; }
}

package_msix() (
    STAGING_DIR=$(mktemp -d)
    trap 'rm -rf -- "$STAGING_DIR"' EXIT
    mkdir "$STAGING_DIR/msix"
    cp -a "$DIR_MSIX/." "$STAGING_DIR/msix/"
    cp "$DIR_DIST/$PROJECT.exe" "$STAGING_DIR/msix/"
    xsltproc \
        --stringparam new-version "$VERSION" \
        "$DIR_THIS_SCRIPT/update-appmanifest.xslt" \
        "$DIR_MSIX/AppxManifest.xml" > "$STAGING_DIR/msix/AppxManifest.xml"

    docker run \
        --rm \
        -v "$STAGING_DIR:/workspace" \
        ghcr.io/soerenkoehler-org/docker-msix:main \
        pack \
        -d "./msix" \
        -p "./$PROJECT.msix"
    [[ -s "$STAGING_DIR/$PROJECT.msix" ]] || { printf "missing MSIX package\n" >&2; exit 1; }
    cp "$STAGING_DIR/$PROJECT.msix" "$DIR_DIST/"
)

release() {
    [[ -s "$DIR_DIST/$PROJECT.exe" && -s "$DIR_DIST/$PROJECT.x64" && -s "$DIR_DIST/$PROJECT.msix" ]] || { printf "missing release artifacts\n" >&2; exit 1; }
    if [[ $GITHUB_REF_TYPE == tag ]]; then
        NOTES_FILE="$DIR_THIS_SCRIPT/release-notes/$RELEASE_TITLE.en-us.txt"
        [[ -f $NOTES_FILE ]] && grep -q '[^[:space:]]' "$NOTES_FILE" || { printf "missing release notes: %s\n" "$NOTES_FILE" >&2; exit 1; }
    fi
    gh auth status >/dev/null

    if [[ $GITHUB_REF_TYPE == tag ]]; then
        create_release_prod
        upload_artifacts
        publish_to_msstore
    else
        create_release_nightly
        upload_artifacts
    fi
}

create_release_prod() {
    if gh release view "$RELEASE" >/dev/null 2>&1; then
        printf "update release notes for '%s'\n" "$RELEASE"
        gh release edit "$RELEASE" --title "$RELEASE_TITLE" --notes-file "$NOTES_FILE"
    else
        printf "create new release '%s'\n" "$RELEASE"
        gh release create \
            --title "$RELEASE_TITLE" \
            --notes-file "$NOTES_FILE" \
            --verify-tag \
            "$RELEASE"
    fi
}

create_release_nightly() {
    printf "create/replace release '%s' on branch %s\n" "$RELEASE" "$GITHUB_REF_NAME"

    fetch_tags

    gh release delete \
        --cleanup-tag \
        --yes \
        "$RELEASE" \
        2>/dev/null || true

    # Workaround for https://github.com/cli/cli/issues/8458
    printf "wait for tag to be deleted\n"
    for ATTEMPT in {1..12}; do
        fetch_tags
        [[ -z $(git tag --list "$RELEASE") ]] && break
        if (( ATTEMPT == 12 )); then
            printf "timed out waiting for nightly tag deletion\n" >&2
            exit 1
        fi
        sleep 10
    done

    gh release create \
        --title "$RELEASE_TITLE" \
        --notes "$(date +'%Y-%m-%d %H:%M:%S')" \
        --target "$GITHUB_SHA" \
        --latest=false \
        "$RELEASE"
}

fetch_tags() {
    git fetch --all --force --tags --prune-tags --prune
}

upload_artifacts() {
    local FILE
    for FILE in "$DIR_DIST/$PROJECT.exe" "$DIR_DIST/$PROJECT.x64" "$DIR_DIST/$PROJECT.msix"; do
        sha256sum "$FILE" > "$FILE.sha256"
    done

    printf "upload artifacts to GitHub release '%s'\n" "$RELEASE"

    for FILE in "$DIR_DIST/$PROJECT.exe" "$DIR_DIST/$PROJECT.x64" "$DIR_DIST/$PROJECT.msix" \
                "$DIR_DIST/$PROJECT.exe.sha256" "$DIR_DIST/$PROJECT.x64.sha256" "$DIR_DIST/$PROJECT.msix.sha256"; do
        gh release upload --clobber "$RELEASE" "$FILE"
    done
}

publish_to_msstore() {
    printf "### login to MS Store\n"

    local VARIABLE DBUS_ENV KEYRING_ENV APP_JSON JSON_OLD JSON_NEW RELEASE_NOTES
    for VARIABLE in MSSTORE_STORE_ID MSSTORE_SELLER_ID MSSTORE_TENANT_ID MSSTORE_CLIENT_ID MSSTORE_CLIENT_SECRET; do
        [[ -n ${!VARIABLE:-} ]] || { printf "missing Store setting: %s\n" "$VARIABLE" >&2; exit 1; }
    done

    DBUS_ENV=$(dbus-launch --sh-syntax)
    eval "$DBUS_ENV"
    printf '%s' 'pipeline_fallback_password' | gnome-keyring-daemon --unlock >/dev/null
    KEYRING_ENV=$(printf '%s' 'pipeline_fallback_password' | gnome-keyring-daemon --start --components=secrets)
    eval "$KEYRING_ENV"

    msstore reconfigure \
        --tenantId     "$MSSTORE_TENANT_ID" \
        --sellerId     "$MSSTORE_SELLER_ID" \
        --clientId     "$MSSTORE_CLIENT_ID" \
        --clientSecret "$MSSTORE_CLIENT_SECRET"

    APP_JSON=$(msstore apps get "$MSSTORE_STORE_ID")
    jq -e 'type == "object" and has("PendingApplicationSubmission") and .PendingApplicationSubmission == null' <<< "$APP_JSON" >/dev/null || {
        printf "Store application has a pending submission (or unknown state); inspect it before publishing\n" >&2
        exit 1
    }

    printf "### stage MSIX package and release notes\n"
    msstore publish "$DIR_DIST/$PROJECT.msix" --appId "$MSSTORE_STORE_ID" --noCommit

    JSON_OLD=$(
        msstore submission get "$MSSTORE_STORE_ID"
    )
    RELEASE_NOTES=$(<"$NOTES_FILE")
    JSON_NEW=$(
        jq -ec <<<"$JSON_OLD" \
            --arg notes "$RELEASE_NOTES" \
            'if (.Listings["en-us"].BaseListing | type) == "object" then
                .Listings["en-us"].BaseListing.ReleaseNotes = $notes
            else
                error("missing en-us BaseListing in Store submission")
            end'
    )
    msstore submission updateMetadata "$MSSTORE_STORE_ID" "$JSON_NEW"
    msstore submission publish "$MSSTORE_STORE_ID"
    msstore submission poll "$MSSTORE_STORE_ID"
}

main "$@"
