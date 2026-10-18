#!/usr/bin/env bash
# Builds the read-only place database and copies it into the app bundle's resources.
#
# Pass --skip-copy to build it without touching App/Antipodes/Resources.
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

step "Building the place database"
python3 -I "$REPO_ROOT/Tools/placedb/build_placedb.py" \
    --seed "$REPO_ROOT/Tools/placedb/seed" \
    --out "$PLACEDB_OUT" \
    ${ARGS+"${ARGS[@]}"}

if [[ "$SKIP_COPY" -eq 0 ]]; then
    mkdir -p "$(dirname "$APP_RESOURCE_DB")"
    cp "$PLACEDB_OUT" "$APP_RESOURCE_DB"
    note "copied into $(basename "$(dirname "$APP_RESOURCE_DB")")/$(basename "$APP_RESOURCE_DB")"
fi
