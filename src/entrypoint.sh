#!/bin/sh
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

set -e

[ $# -gt 0 ] || set -- glowingbear
if [ "$1" == "glowingbear" ]; then
    VERSION="$(sed -ne 's/^VERSION=\(.*\)$/\1/p' /usr/src/glowingbear/version_info)"

    # update Glowing Bear source files
    echo "Initializing Glowing Bear $VERSION..."
    rsync -rlptog --delete --chown glowingbear:glowingbear \
        "/usr/src/glowingbear/glowingbear/" \
        "/var/www/html/"

    rsync -lptog --chown glowingbear:glowingbear \
        "/usr/src/glowingbear/version_info" \
        "/var/www/glowingbear_version_info"

    # do nothing, Glowing Bear is just a static website ;-)
    echo "Sleeping..."
    sleep infinity
fi

exec "$@"
