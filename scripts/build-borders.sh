#!/usr/bin/env bash
# Builds the bundled country-border files from the Natural Earth downloads.
#
# Run scripts/fetch-borders.sh first. If the downloads are missing this skips with a
# note rather than failing, so scripts/check.sh still passes on a machine with no
# network: the globe then renders without country shading and says so.
#
# Pass --skip-copy to build without touching App/Antipodes/Resources.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require python3

SKIP_COPY=0
for argument in "$@"; do
    case "$argument" in
        --skip-copy) SKIP_COPY=1 ;;
        *) fail "unknown argument: $argument" ;;
    esac
done

build_one() {
    local resolution="$1" scale="$2"
    local source_file="$BORDERS_VENDOR/ne_${resolution}_admin_0_countries.geojson"
    local out_file="$BORDERS_OUT/borders-${resolution}.antborders"

    if [[ ! -f "$source_file" ]]; then
        note "missing $(basename "$source_file") — skipping ${resolution}"
        return 1
    fi

    step "Building ${resolution} borders"
    # Checked explicitly: `set -e` does not apply inside a function called as part of
    # an && list, so a failing build would otherwise fall through to the copy.
    python3 -I "$REPO_ROOT/Tools/placedb/build_borders.py" \
        --geojson "$source_file" \
        --scale "$scale" \
        --out "$out_file" \
        || fail "could not build ${resolution} borders"

    if [[ "$SKIP_COPY" -eq 0 ]]; then
        mkdir -p "$APP_RESOURCE_DIR"
        cp "$out_file" "$APP_RESOURCE_DIR/$(basename "$out_file")" \
            || fail "could not copy $(basename "$out_file") into the app resources"
        note "copied into Resources/$(basename "$out_file")"
    fi
}

BUILT=0
build_one 110m 110 && BUILT=$((BUILT + 1))
build_one 50m 50 && BUILT=$((BUILT + 1))

if [[ "$BUILT" -eq 0 ]]; then
    note "no border files built — run scripts/fetch-borders.sh to download the source"
    note "the globe still renders; it just shades no countries"
fi
