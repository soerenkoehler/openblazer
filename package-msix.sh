#!/bin/bash

main() {
    THIS_SCRIPT=$(readlink -e "$0")
    DIR_THIS_SCRIPT=$(dirname "$THIS_SCRIPT")

    PROJECT=$(
        grep -E '^config/name=".+"' "./game/project.godot" \
        | cut -d'=' -f2 \
        | tr -d '"'
    )

    docker run \
        --rm \
        -v "$PWD":"/workspace" \
        ghcr.io/soerenkoehler-org/docker-msix:main \
        pack \
        -d "./msix" \
        -p "./$PROJECT.msix"
}

main "$@"
