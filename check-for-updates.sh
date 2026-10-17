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
source "$CI_TOOLS_PATH/helper/github.sh.inc"
source "$CI_TOOLS_PATH/helper/chkupd.sh.inc"

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$BUILD_DIR/container.env"

[ -n "${VERSION:-}" ] \
    || { echo "Invalid build environment: Incomplete version information" >&2; exit 1; }

TAG="${TAGS%% *}"

# check whether the image is using the given version
chkupd_image_version "$REGISTRY/$OWNER/$IMAGE:$TAG" "$VERSION" || exit 0

# check whether the base image was updated
# since Glowing Bear is just a static website, no binaries run inside the container (besides `sleep infinity`)
# thus there's no need to keep the base image strictly updated, just make sure to rebuild at least once a month
if ! chkupd_image_age "$REGISTRY/$OWNER/$IMAGE" "$TAG" "+1 month" > /dev/null; then
    echo "Defering rebuild decision, check whether base image is still up-to-date..." >&2

    chkupd_baseimage "$REGISTRY/$OWNER/$IMAGE" "$TAG" || exit 0
fi
