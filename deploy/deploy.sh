#!/bin/bash

main() {
    THIS_SCRIPT=$(readlink -e "$0")
    DIR_THIS_SCRIPT=$(dirname "$THIS_SCRIPT")
    DIR_GAME=$(readlink -e "./game")
    DIR_DIST=$(readlink -e "./dist")

    PROJECT=$(
        grep -E '^config/name=".+"' "$DIR_GAME/project.godot" \
        | cut -d'=' -f2 \
        | tr -d '"'
    )
    GODOT_VERSION=4.6.2-stable

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

    # set release mode
    if [[ $GITHUB_REF_TYPE == 'tag' ]]; then
        RELEASE="$GITHUB_REF_NAME"
        if [[ $RELEASE =~ ^v([0-9]+\.[0-9]+\.[0-9]+) ]]; then
            VERSION="${BASH_REMATCH[1]}"
        else
            printf "tag name %s does not begin with required semver 'vMAJOR.MINOR.PATCH'\n" "$GITHUB_REF_NAME"
            exit -1
        fi
    elif [[ $GITHUB_REF_TYPE == 'branch' ]]; then
        RELEASE=nightly
    fi
}

install_godot() {
    for FILE in linux.x86_64.zip export_templates.tpz
    do
        curl \
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
    # export Godot projects

    ./godot --headless --path "$DIR_GAME" --export-release "Windows Desktop" "$DIR_DIST/$PROJECT.exe"
    ./godot --headless --path "$DIR_GAME" --export-release "Linux"           "$DIR_DIST/$PROJECT.x64"

    # create MSIX package

    cp "$DIR_DIST/$PROJECT.exe" "./msix/"

    docker run \
        --rm \
        -v "$PWD":"/workspace" \
        ghcr.io/soerenkoehler-org/docker-msix:main \
        pack \
        -d "./msix" \
        -p "./dist/$PROJECT.msix"
    xsltproc \
        --stringparam new-version "$VERSION" \
        update-appmanifest.xslt \
        AppxManifest.xml > AppxManifest.updated.xml

    # create SHA256 hashes

    pushd "$DIST_DIR"

    rm *.sha256
    for FILE in *
    do
        sha256sum "$FILE" >$FILE.sha256
    done

    popd
}

release() {
    printf "verify github auth status:\n%s\n\n" "$(gh auth status)"

    # first (quick win): create and upload GitHub release
    if [[ $RELEASE == nightly ]]; then
        create_release_prod
    else
        create_release_nightly
    fi

    upload_artifacts

    # second (long duration): publish to MS Store
    # FIXME if [[ $RELEASE != nightly ]]; then
        # publish_to_msstore
    # fi
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
    printf "uploading artifacts to GitHub release '%s'\n" "$RELEASE"

    gh release upload --clobber "$RELEASE" "$DIR_DIST/*"
}

publish_to_msstore() {
    sudo apt-get update
    sudo apt-get install -y \
        libsecret-1-0 \
        gnome-keyring \
        dbus-x11

    eval $(
        dbus-launch --sh-syntax
    )
    printf "pipeline_fallback_password" \
    | gnome-keyring-daemon --unlock
    eval $(
        printf "pipeline_fallback_password" \
        | gnome-keyring-daemon --start --components=secrets
    )

    msstore reconfigure \
        --tenantId     "$MSSTORE_TENANT_ID" \
        --sellerId     "$MSSTORE_SELLER_ID" \
        --clientId     "$MSSTORE_CLIENT_ID" \
        --clientSecret "$MSSTORE_CLIENT_SECRET"

    printf "uploading artifacts to MS Store\n"

    msstore publish \
        "./$PROJECT.msix" \
        --verbose \
        --appId "$MSSTORE_STORE_ID"
}

main "$@"
