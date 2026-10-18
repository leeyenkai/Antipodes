#!/usr/bin/env bash
# Downloads the Natural Earth country borders the globe screen draws.
#
# This is the one script in the repository that needs a network connection. The app
# never does: these files are a build input, compiled into the bundled border file by
# scripts/build-borders.sh (R-GLOBE-2, decision D-5).
#
# Natural Earth is public domain, which is the reason it is the source. The ODbL
# share-alike question for a shipped derived database is unresolved (R-DB-7), so
# OpenStreetMap geometry must not reach the bundle. See Tools/placedb/SOURCES.md.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require curl
require shasum

# Pinned to a tagged release so a rebuild fetches the same geometry rather than
# whatever master holds today, and verified against its digest.
#
# scripts/fetch-placedb-sources.sh already caches ne_110m into the same directory for
# the country list, pinned to this same tag and digest (see Tools/placedb/sources.py,
# which says so). This script skips any file already there and verified, so running
# both only fetches ne_50m, which the globe needs and the place database does not.
NE_TAG="v5.1.2"
NE_BASE="https://raw.githubusercontent.com/nvkelso/natural-earth-vector/$NE_TAG/geojson"

SHA_110M="6866c877d39cba9c357620878839b336d569f8c662d3cfab4cb1dbe2d39c977f"
SHA_50M="3e458fc036ad0a66411f2c1e6cac49c5d7bfb81cb1123bc513b22511a2b7fdeb"

mkdir -p "$BORDERS_VENDOR"

fetch() {
    local resolution="$1" expected="$2"
    local name="ne_${resolution}_admin_0_countries.geojson"
    local destination="$BORDERS_VENDOR/$name"

    if [[ -f "$destination" ]] && [[ "$(shasum -a 256 "$destination" | cut -d' ' -f1)" == "$expected" ]]; then
        note "$name already present and verified"
        return
    fi

    step "Fetching $name ($NE_TAG)"
    curl -fsSL --max-time 300 -o "$destination.partial" "$NE_BASE/$name" \
        || fail "could not download $name"

    local actual
    actual="$(shasum -a 256 "$destination.partial" | cut -d' ' -f1)"
    if [[ "$actual" != "$expected" ]]; then
        rm -f "$destination.partial"
        fail "$name digest mismatch: expected $expected, got $actual"
    fi
    mv "$destination.partial" "$destination"
    note "verified sha256:${expected:0:16}"
}

fetch 110m "$SHA_110M"
fetch 50m "$SHA_50M"

step "Natural Earth borders ready in Tools/placedb/vendor/naturalearth"
note "now run scripts/build-borders.sh"
