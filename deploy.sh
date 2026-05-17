#!/bin/bash

main() {
    THIS_SCRIPT=$(readlink -e "$0")
    DIR_THIS_SCRIPT=$(dirname "$THIS_SCRIPT")

    PROJECT=$(
        grep -E '^config/name=".+"' "./game/project.godot" \
        | cut -d'=' -f2 \
        | tr -d '"'
    )
    GODOT_VERSION=4.6.2

    initialize_workspace

    case $1 in

    install)
        install_godot
    ;;

    package)
        rm -r "$DIR_DIST/*"
        package
    ;;

    release)
        release
    ;;

    *)
        printf "missing or wrong command: %s\n" "$2"
    ;;

    esac
}

initialize_workspace() {
    # check working dir
    if [[ ! -e "$PROJECT.code-workspace" ]]; then
        printf "not in project root\n"
        exit -1
    fi

    # prepare output directories
    DIR_DIST=./dist

    for DIR in $DIR_DIST; do
        mkdir -v -p $DIR
        chmod -v 777 $DIR
    done
}

install_godot() {
    for FILE in linux.x86_64.zip export_templates.tpz
    do
        curl \
            --location \
            --remote-name \
            "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_${FILE}"
    done
}

package() {
    printf "TODO\n"
}

release() {
    printf "verify github auth status:\n%s\n\n" "$(gh auth status)"

    if [[ $GITHUB_REF_TYPE == 'tag' ]]; then
        create_release_prod
    elif [[ $GITHUB_REF_TYPE == 'branch' ]]; then
        create_release_nightly
    fi

    if [[ -e $DIR_DIST ]]; then
        upload_artifacts
    else
        printf "no artifacts to upload\n"
    fi
}

create_release_prod() {
    RELEASE=$GITHUB_REF_NAME

    local EXISTING=$(
        gh release list \
            --json tagName \
            --jq 'map(.tagname)[0]'
    )

    if [[ -z $EXISTING ]]; then
        printf "create new release '%s'\n" "$RELEASE"
        gh release create \
            --title "$RELEASE" \
            --notes "$(date +'%Y-%m-%d %H:%M:%S')" \
            --verify-tag \
            "$RELEASE"
    else
        printf "use existing release '%s'\n" "$RELEASE"
    fi
}

create_release_nightly() {
    RELEASE=nightly

    printf "create/replace release 'nightly' on branch %s\n" "$GITHUB_REF_NAME"

    fetch_tags

    gh release delete \
        --cleanup-tag \
        --yes \
        "$RELEASE" \
        2>/dev/null || true

    # Workaround for https://github.com/cli/cli/issues/8458
    printf "waiting for tag to be deleted\n"
    while fetch_tags; git tag -l | grep "$RELEASE"; do
        sleep 10;
        printf "still waiting...\n"
    done

    fetch_tags

    gh release create \
        --title "Nightly" \
        --notes "$(date +'%Y-%m-%d %H:%M:%S')" \
        --target "$GITHUB_REF" \
        --latest=false \
        "$RELEASE"

    fetch_tags
}

fetch_tags() {
    git fetch --all --force --tags --prune-tags --prune
}

upload_artifacts() {
    printf "uploading artifacts to '%s'\n" "$RELEASE"

    gh release upload --clobber "$RELEASE" "$DIR_DIST/*"
}

main "$@"
