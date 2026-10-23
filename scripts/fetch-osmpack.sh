#!/usr/bin/env bash
# Downloads the OpenStreetMap data the route pack is built from (D-36), into
# Tools/osmpack/vendor/osm/. Hours, not minutes: the public Overpass server answers a
# query in about half a minute and allows two at once, so the transit and the trails are
# fetched side by side. An interrupted fetch resumes where it stopped.
#
# Pass a part to fetch only that: routes, lifts, transit or trails.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require python3

step "Fetching OpenStreetMap data (ODbL) for the route pack"
if [[ $# -gt 0 ]]; then
    ARGS=()
    for part in "$@"; do ARGS+=(--only "$part"); done
    python3 -I "$OSMPACK_DIR/fetch_osm.py" "${ARGS[@]}"
else
    python3 -I "$OSMPACK_DIR/fetch_osm.py" --only routes --only lifts --only transit &
    first=$!
    python3 -I "$OSMPACK_DIR/fetch_osm.py" --only trails
    wait "$first"
fi
