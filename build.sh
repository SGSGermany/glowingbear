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

if [ -n "${VERSION:-}" ] && [ -n "${HASH:-}" ]; then
    echo + "[[ $(quote "$VERSION") =~ ^([0-9]+\.[0-9]+\.[0-9]+-([a-f0-9]+))([+~-]|$) ]]" >&2
    if ! [[ "$VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+-([a-f0-9]+))([+~-]|$) ]]; then
        echo "Invalid build environment: Environment variable 'VERSION' is invalid: $VERSION" >&2
        exit 1
    fi

    echo + "HASH_SHORT=\"\${BASH_REMATCH[2]}\"" >&2
    HASH_SHORT="${BASH_REMATCH[2]}"

    echo + "[[ $(quote "$HASH") =~ ^[a-f0-9]{40}[a-f0-9]{24}?$ ]]" >&2
    if ! [[ "$HASH" =~ ^[a-f0-9]{40}[a-f0-9]{24}?$ ]]; then
        echo "Invalid build environment: Environment variable 'HASH' is invalid: $HASH" >&2
        exit 1
    fi

    echo + "[[ $(quote "$HASH") == $(quote "$HASH_SHORT")* ]]" >&2
    if [[ "$HASH" != "$HASH_SHORT"* ]]; then
        echo "Invalid build environment: Environment variables 'VERSION' (${VERSION@Q})" \
            "and 'HASH' (${HASH@Q}) contradict each other" >&2
        exit 1
    fi

    git_clone "$GIT_REPO" "$HASH" \
        "$BUILD_MOUNT/usr/src/glowingbear" "<builder> …/usr/src/glowingbear"
else
    git_clone "$GIT_REPO" "$GIT_REF" \
        "$BUILD_MOUNT/usr/src/glowingbear" "<builder> …/usr/src/glowingbear"

    echo + "HASH=\"\$(git -C '<builder> …/usr/src/glowingbear' rev-parse HEAD)\"" >&2
    HASH="$(git -C "$BUILD_MOUNT/usr/src/glowingbear" rev-parse HEAD)"

    echo + "HASH_SHORT=\"\$(git -C '<builder> …/usr/src/glowingbear' rev-parse --short HEAD)\"" >&2
    HASH_SHORT="$(git -C "$BUILD_MOUNT/usr/src/glowingbear" rev-parse --short HEAD)"

    echo + "VERSION=\"\$(jq -re '.version' '<builder> …/usr/src/glowingbear/package.json')-\$HASH_SHORT\"" >&2
    VERSION="$(jq -re '.version' "$BUILD_MOUNT/usr/src/glowingbear/package.json")-$HASH_SHORT"
fi

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
        HASH "$HASH"

cmd buildah run "$CONTAINER" -- \
    chown glowingbear:glowingbear "/var/www/html"

cleanup "$CONTAINER"

con_cleanup "$CONTAINER"

cmd buildah config \
    --env GLOWING_BEAR_VERSION="$VERSION" \
    --env GLOWING_BEAR_HASH="$HASH" \
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
    --annotation org.opencontainers.image.created="$(date -u +'%+4Y-%m-%dT%H:%M:%SZ')" \
    "$CONTAINER"

con_commit "$CONTAINER" "$IMAGE" "${TAGS[@]}"
