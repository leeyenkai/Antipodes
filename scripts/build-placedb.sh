#!/usr/bin/env bash
# Builds the read-only place database and copies it into the app bundle's resources.
#
# The build itself needs no network. If the source cache is not there yet, this fetches
# it once (scripts/fetch-placedb-sources.sh); after that every rebuild is offline and
# reproducible from the cached inputs.
#
# Pass --skip-copy to build without touching App/Antipodes/Resources.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require python3

SKIP_COPY=0
ARGS=()
for argument in "$@"; do
    case "$argument" in
        --skip-copy) SKIP_COPY=1 ;;
        *) ARGS+=("$argument") ;;
    esac
done

if [[ ! -f "$PLACEDB_MANIFEST" ]]; then
    note "no source cache yet — fetching once"
    "$REPO_ROOT/scripts/fetch-placedb-sources.sh"
fi

step "Building the place database"
python3 -I "$REPO_ROOT/Tools/placedb/build_placedb.py" \
    --out "$PLACEDB_OUT" \
    ${ARGS+"${ARGS[@]}"}

if [[ "$SKIP_COPY" -eq 0 ]]; then
    mkdir -p "$APP_RESOURCE_DIR"
    cp "$PLACEDB_OUT" "$APP_RESOURCE_DB"
    note "copied into $(basename "$APP_RESOURCE_DIR")/$(basename "$APP_RESOURCE_DB")"
fi
