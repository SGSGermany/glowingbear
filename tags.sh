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
source "$CI_TOOLS_PATH/helper/common-traps.sh.inc"
source "$CI_TOOLS_PATH/helper/git.sh.inc"

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$BUILD_DIR/container.env"

BUILD_INFO=""
if [ $# -gt 0 ] && [[ "$1" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    BUILD_INFO=".${1,,}"
fi

# use VERSION variable in container.env
echo + "SOURCE_DIR=\"\$(mktemp -d)\"" >&2
SOURCE_DIR="$(mktemp -d)"

trap_exit rm -rf "$SOURCE_DIR"

git_clone "$GIT_REPO" "$GIT_REF" \
    "$SOURCE_DIR" "$SOURCE_DIR"

echo + "HASH=\"\$(git -C $(quote "$SOURCE_DIR") rev-parse HEAD)\"" >&2
HASH="$(git -C "$SOURCE_DIR" rev-parse HEAD)"

echo + "HASH_SHORT=\"\$(git -C $(quote "$SOURCE_DIR") rev-parse --short HEAD)\"" >&2
HASH_SHORT="$(git -C "$SOURCE_DIR" rev-parse --short HEAD)"

echo + "VERSION=\"\$(jq -re '.version' -C $(quote "$SOURCE_DIR/package.json")\"" >&2
VERSION="$(jq -re '.version' "$SOURCE_DIR/package.json")"

if [ -z "$VERSION" ]; then
    echo "Unable to read Glowing Bear version from '$SOURCE_DIR/package.json': Version not found" >&2
    exit 1
elif ! [[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)([+~-]|$) ]]; then
    echo "Unable to read Glowing Bear version from '$SOURCE_DIR/package.json': '$VERSION' is no valid version" >&2
    exit 1
fi

VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
VERSION_MINOR="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
VERSION_MAJOR="${BASH_REMATCH[1]}"

# build tags
BUILD_INFO="$(date --utc +'%Y%m%d')$BUILD_INFO"

TAGS=(
    "v$VERSION-$HASH_SHORT" "v$VERSION-$HASH_SHORT-$BUILD_INFO"
    "v$VERSION" "v$VERSION-$BUILD_INFO"
    "v$VERSION_MINOR" "v$VERSION_MINOR-$BUILD_INFO"
)

[ "$VERSION_MAJOR" == "0" ] \
    || TAGS+=( "v$VERSION_MAJOR" "v$VERSION_MAJOR-$BUILD_INFO" )

TAGS+=( "latest" )

printf 'VERSION="%s"\n' "$VERSION-$HASH_SHORT"
printf 'HASH="%s"\n' "$HASH"
printf 'TAGS="%s"\n' "${TAGS[*]}"
