#!/bin/bash
# Glowing Bear
# A container running Glowing Bear, a web frontend for the WeeChat IRC client.
#
# Copyright (c) 2023  SGS Serious Gaming & Simulations GmbH
#
# This work is licensed under the terms of the MIT license.
# For a copy, see LICENSE file or <https://opensource.org/licenses/MIT>.
#
# SPDX-License-Identifier: MIT
# License-Filename: LICENSE

set -eu -o pipefail
export LC_ALL=C.UTF-8

[ -v CI_TOOLS ] && [ "$CI_TOOLS" == "SGSGermany" ] \
    || { echo "Invalid build environment: Environment variable 'CI_TOOLS' not set or invalid" >&2; exit 1; }

[ -v CI_TOOLS_PATH ] && [ -d "$CI_TOOLS_PATH" ] \
    || { echo "Invalid build environment: Environment variable 'CI_TOOLS_PATH' not set or invalid" >&2; exit 1; }

source "$CI_TOOLS_PATH/helper/common.sh.inc"
source "$CI_TOOLS_PATH/helper/common-traps.sh.inc"
source "$CI_TOOLS_PATH/helper/git.sh.inc"
source "$CI_TOOLS_PATH/helper/chkupd.sh.inc"

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$BUILD_DIR/container.env"

TAG="${TAGS%% *}"

# check whether the image is using the latest Glowing Bear dev version
if [ -z "${VERSION:-}" ]; then
    # check whether the Git repository indicates a new version
    echo + "SOURCE_DIR=\"\$(mktemp -d)\"" >&2
    SOURCE_DIR="$(mktemp -d)"

    trap_exit rm -rf "$SOURCE_DIR"

    git_clone "$GIT_REPO" "$GIT_REF" \
        "$SOURCE_DIR" "$SOURCE_DIR"

    echo + "VERSION=\"\$(jq -re '.version' -C $(quote "$SOURCE_DIR/package.json")\"" >&2
    VERSION="$(jq -re '.version' "$SOURCE_DIR/package.json")"

    if [ -z "$VERSION" ]; then
        echo "Unable to read Glowing Bear version from '$SOURCE_DIR/package.json': Version not found" >&2
        exit 1
    elif ! [[ "$VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)([+~-]|$) ]]; then
        echo "Unable to read Glowing Bear version from '$SOURCE_DIR/package.json': '$VERSION' is no valid version" >&2
        exit 1
    fi

    echo + "HASH_SHORT=\"\$(git -C $(quote "$SOURCE_DIR") rev-parse --short HEAD)\"" >&2
    HASH_SHORT="$(git -C "$SOURCE_DIR" rev-parse --short HEAD)"

    echo + "VERSION=\"${BASH_REMATCH[1]}-$HASH_SHORT\"" >&2
    VERSION="${BASH_REMATCH[1]}-$HASH_SHORT"
fi

chkupd_image_version "$REGISTRY/$OWNER/$IMAGE:$TAG" "$VERSION" || exit 0

# check whether the base image was updated
# since Glowing Bear is just a static website, no binaries run inside the container (besides `sleep infinity`)
# thus there's no need to keep the base image strictly updated, just make sure to rebuild at least once a month
chkupd_image_age() {
    local IMAGE="$1"
    local TAG="$2"
    local RELATIVE_AGE="$3"

    # pull current image
    echo + "IMAGE_ID=\"\$(podman pull $(quote "$IMAGE:$TAG"))\"" >&2
    local IMAGE_ID="$(podman pull "$IMAGE:$TAG" || true)"

    if [ -z "$IMAGE_ID" ]; then
        echo "Failed to pull image '$IMAGE:$TAG': No image with this tag found" >&2
        echo "Image rebuild required" >&2
        echo "build"
        return 1
    fi

    # check whether image is older than the maximum age given
    # Note: Go uses the magic date '2006-01-02 15:04:05.999999999 -07:00' as reference for date formatting
    echo + "CREATED=\"\$(podman image inspect --format '{{.Created.Format "2006-01-02T15:04:05-07:00"}}' $IMAGE_ID)\"" >&2
    local CREATED="$(podman image inspect --format '{{.Created.Format "2006-01-02T15:04:05-07:00"}}' "$IMAGE_ID" || true)"

    if [ -z "$CREATED" ]; then
        echo "Failed to inspect image '$IMAGE:$TAG': The image specifies no creation date" >&2
        echo "Image rebuild required" >&2
        echo "build"
        return 1
    fi

    echo + "REBUILD_AFTER=\"\$(date --date=$(quote "$CREATED $RELATIVE_AGE") +'%s')\"" >&2
    local REBUILD_AFTER="$(date --date="$CREATED $RELATIVE_AGE" +'%s' || true)"

    if [ -z "$REBUILD_AFTER" ]; then
        echo "Failed to inspect image '$IMAGE:$TAG': The calculated maximum image age is invalid: $CREATED $RELATIVE_AGE" >&2
        echo "Image rebuild required" >&2
        echo "build"
        return 1
    fi

    echo + "[[ $(quote "$(date --date="@$REBUILD_AFTER" +'%F %T')") < $(quote "$(date +'%F %T')") ]]" >&2
    if [[ "$REBUILD_AFTER" < "$(date +'%s')" ]]; then
        echo "Image reached its end of life as of $(date +'%F %T')" >&2
        echo "Image creation date: $(date --date="$CREATED" +'%F %T')" >&2
        echo "Image rebuild required after: $(date --date="@$REBUILD_AFTER" +'%F %T')" >&2
        echo "Image rebuild required" >&2
        echo "build"
        return 1
    fi
}

if ! chkupd_image_age "$REGISTRY/$OWNER/$IMAGE" "$TAG" "+1 month" > /dev/null 2>&1; then
    chkupd_baseimage "$REGISTRY/$OWNER/$IMAGE" "$TAG" || exit 0
fi
