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

[ -x "$(which jq 2>/dev/null)" ] \
    || { echo "Missing build script dependency: jq" >&2; exit 1; }

[ -x "$(which sponge 2>/dev/null)" ] \
    || { echo "Missing build script dependency: sponge" >&2; exit 1; }

source "$CI_TOOLS_PATH/helper/common.sh.inc"
source "$CI_TOOLS_PATH/helper/container.sh.inc"
source "$CI_TOOLS_PATH/helper/container-alpine.sh.inc"
source "$CI_TOOLS_PATH/helper/git.sh.inc"

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$BUILD_DIR/container.env"

readarray -t -d' ' TAGS < <(printf '%s' "$TAGS")

echo + "BUILD_CONTAINER=\"\$(buildah from $(quote "$BASE_IMAGE"))\"" >&2
BUILD_CONTAINER="$(buildah from "$BASE_IMAGE")"

echo + "BUILD_MOUNT=\"\$(buildah mount $(quote "$BUILD_CONTAINER"))\"" >&2
BUILD_MOUNT="$(buildah mount "$BUILD_CONTAINER")"

git_clone "$GIT_REPO" "$GIT_COMMIT" \
    "$BUILD_MOUNT/usr/src/glowingbear" "<builder> …/usr/src/glowingbear"

pkg_install "$BUILD_CONTAINER" \
    nodejs \
    npm@community

cmd buildah run --workingdir "/usr/src/glowingbear" "$BUILD_CONTAINER" -- \
    npm install

cmd buildah run --workingdir "/usr/src/glowingbear" "$BUILD_CONTAINER" -- \
    npm run build

echo + "CONTAINER=\"\$(buildah from $(quote "$BASE_IMAGE"))\"" >&2
CONTAINER="$(buildah from "$BASE_IMAGE")"

echo + "MOUNT=\"\$(buildah mount $(quote "$CONTAINER"))\"" >&2
MOUNT="$(buildah mount "$CONTAINER")"

user_add "$CONTAINER" glowingbear 65536 "/var/lib/glowingbear"

pkg_install "$CONTAINER" --virtual .run-deps \
    rsync

echo + "rsync -v -rl --exclude .gitignore ./src/ …/" >&2
rsync -v -rl --exclude '.gitignore' "$BUILD_DIR/src/" "$MOUNT/"

echo + "rsync -v -rl '<builder> …/usr/src/glowingbear/build/' …/usr/src/glowingbear/glowingbear/" >&2
rsync -v -rl "$BUILD_MOUNT/usr/src/glowingbear/build/" "$MOUNT/usr/src/glowingbear/glowingbear/"

echo + "rm -f …/usr/src/glowingbear/glowingbear/package.json" >&2
rm -f "$MOUNT/usr/src/glowingbear/glowingbear/package.json"

echo + "jq -e --arg VERSION $(quote "$VERSION") '.version = \$VERSION' …/usr/src/glowingbear/glowingbear/manifest.json | sponge …" >&2
jq -e --arg VERSION "$VERSION" '.version = $VERSION' "$MOUNT/usr/src/glowingbear/glowingbear/manifest.json" \
    | sponge "$MOUNT/usr/src/glowingbear/glowingbear/manifest.json"

echo + "jq -e --arg VERSION $(quote "$VERSION") '.version = \$VERSION' …/usr/src/glowingbear/glowingbear/manifest.webapp | sponge …" >&2
jq -e --arg VERSION "$VERSION" '.version = $VERSION' "$MOUNT/usr/src/glowingbear/glowingbear/manifest.webapp" \
    | sponge "$MOUNT/usr/src/glowingbear/glowingbear/manifest.webapp"

echo + "sed -i -e \"s/>Glowing Bear version [^<]*</>Glowing Bear version \$VERSION</\" …/usr/src/glowingbear/glowingbear/index.html" >&2
sed -i -e "s/>Glowing Bear version [^<]*</>Glowing Bear version $(sed -e 's/[\/&]/\\&/g' <<< "$VERSION")</" \
    "$MOUNT/usr/src/glowingbear/glowingbear/index.html"

cmd buildah run "$CONTAINER" -- \
    /bin/sh -c "printf '%s=%s\n' \"\$@\" > /usr/src/glowingbear/version_info" -- \
        VERSION "$VERSION" \
        HASH "$GIT_COMMIT"

cmd buildah run "$CONTAINER" -- \
    chown glowingbear:glowingbear "/var/www/html"

cleanup "$CONTAINER"

cmd buildah config \
    --env GLOWING_BEAR_VERSION="$VERSION" \
    --env GLOWING_BEAR_HASH="$GIT_COMMIT" \
    "$CONTAINER"

cmd buildah config \
    --volume "/var/www" \
    "$CONTAINER"

cmd buildah config \
    --workingdir "/var/www/html" \
    --entrypoint '[ "/entrypoint.sh" ]' \
    --cmd '[ "glowingbear" ]' \
    "$CONTAINER"

cmd buildah config \
    --annotation org.opencontainers.image.title="Glowing Bear" \
    --annotation org.opencontainers.image.description="A container running Glowing Bear, a web frontend for the WeeChat IRC client." \
    --annotation org.opencontainers.image.version="$VERSION" \
    --annotation org.opencontainers.image.url="https://github.com/SGSGermany/glowingbear" \
    --annotation org.opencontainers.image.authors="SGS Serious Gaming & Simulations GmbH" \
    --annotation org.opencontainers.image.vendor="SGS Serious Gaming & Simulations GmbH" \
    --annotation org.opencontainers.image.licenses="MIT" \
    --annotation org.opencontainers.image.base.name="$BASE_IMAGE" \
    --annotation org.opencontainers.image.base.digest="$(podman image inspect --format '{{.Digest}}' "$BASE_IMAGE")" \
    "$CONTAINER"

con_commit "$CONTAINER" "$IMAGE" "${TAGS[@]}"
