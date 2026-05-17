#!/bin/bash

main() {
    THIS_SCRIPT=$(readlink -e "$0")
    DIR_THIS_SCRIPT=$(dirname "$THIS_SCRIPT")

    case $1 in

    package)
        if [[ -z $2 ]]; then
            printf "%s\n" \
                "usage:" \
                "docker-rs.sh package TARGET_ARTIFACT_NAME"
            exit -1
        fi
        initialize_workspace
        rm -r $DIR_DIST/*
        package $2
    ;;

    release)
        initialize_workspace
        release
    ;;

    *)
        printf "missing or wrong command\n"
    ;;

    esac
}

initialize_workspace() {
    # check working dir
    if [[ ! -e openblazer.code-workspace ]]; then
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

    local EXISTING=$(gh release list \
        --json tagName \
        --jq "[.[] | select(.tagName == \"$RELEASE\").tagName][0]")

    if [[ -z $EXISTING ]]; then
        printf "create new release '%s'\n" $RELEASE
        gh release create \
            --title $RELEASE \
            --notes "$(date +'%Y-%m-%d %H:%M:%S')" \
            --verify-tag \
            $RELEASE
    else
        printf "use existing release '%s'\n" $RELEASE
    fi
}

create_release_nightly() {
    RELEASE=nightly

    printf "create/replace release 'nightly' on branch %s\n" $GITHUB_REF_NAME

    fetch_tags

    gh release delete \
        --cleanup-tag \
        --yes \
        $RELEASE \
        2>/dev/null || true

    # Workaround for https://github.com/cli/cli/issues/8458
    printf "waiting for tag to be deleted\n"
    while fetch_tags; git tag -l | grep $RELEASE; do
        sleep 10;
        printf "still waiting...\n"
    done

    fetch_tags

    gh release create \
        --title "Nightly" \
        --notes "$(date +'%Y-%m-%d %H:%M:%S')" \
        --target $GITHUB_REF \
        --latest=false \
        $RELEASE

    fetch_tags
}

fetch_tags() {
    git fetch --all --force --tags --prune-tags --prune
}

upload_artifacts() {
    printf "uploading artifacts to '%s'\n" $RELEASE

    gh release upload --clobber $RELEASE $DIR_DIST/*
}

main "$@"
