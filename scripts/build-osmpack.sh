#!/usr/bin/env bash
# Builds routes-osm.sqlite, the OpenStreetMap route pack (D-36), from the cache that
# scripts/fetch-osmpack.sh fills, and copies it into the app bundle's resources. The
# build needs no network, and reads the place database to know its routes and lines, so
# scripts/build-placedb.sh comes first.
#
# Pass --skip-copy to build without touching App/Antipodes/Resources.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require python3

SKIP_COPY=0
for argument in "$@"; do
    [[ "$argument" == "--skip-copy" ]] && SKIP_COPY=1
done

if [[ ! -f "$OSMPACK_DIR/vendor/osm/manifest.json" ]]; then
    fail "no OpenStreetMap cache yet. Run scripts/fetch-osmpack.sh first (it takes hours)."
fi
[[ -f "$APP_RESOURCE_DB" ]] || "$REPO_ROOT/scripts/build-placedb.sh"

step "Building the OpenStreetMap route pack"
python3 -I "$OSMPACK_DIR/build_osmpack.py" --places "$APP_RESOURCE_DB" --out "$OSMPACK_OUT"

if [[ "$SKIP_COPY" -eq 0 ]]; then
    mkdir -p "$APP_RESOURCE_DIR"
    cp "$OSMPACK_OUT" "$APP_RESOURCE_PACK"
    note "copied into $(basename "$APP_RESOURCE_DIR")/$(basename "$APP_RESOURCE_PACK")"
fi
