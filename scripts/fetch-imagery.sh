#!/usr/bin/env bash
# Downloads NASA's Blue Marble picture of the Earth and prepares the copy the
# satellite globe wraps round the sphere (decision D-26).
#
# Like the country borders, this is a build input: the app never fetches imagery, so
# the satellite globe works in airplane mode and turning it sends nothing anywhere
# (R-PRIV-7, D-5). Blue Marble Next Generation is NASA imagery and public domain; the
# credit NASA asks for is shown in Settings › Data Sources (Tools/placedb/SOURCES.md).
#
# The download is pinned to one file and verified against its digest, then scaled to
# 4096 × 2048 with sips, which is plenty for a phone-sized globe and decodes to 32 MB.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require curl
require shasum
require sips

# August 2004, with topography and bathymetry: northern summer, so the least snow on
# the land most people live on, and the sea floor shaded rather than flat blue.
NAME="world.topo.bathy.200408.3x5400x2700.jpg"
URL="https://eoimages.gsfc.nasa.gov/images/imagerecords/73000/73776/$NAME"
SHA="f76d7b94445e8975a755c849ddaa93ed07b7e01118fb0b7e6bc5546a68c18d5c"

DESTINATION="$IMAGERY_VENDOR/$NAME"
mkdir -p "$IMAGERY_VENDOR" "$BORDERS_OUT"

if [[ -f "$DESTINATION" ]] && [[ "$(shasum -a 256 "$DESTINATION" | cut -d' ' -f1)" == "$SHA" ]]; then
    note "$NAME already present and verified"
else
    step "Fetching $NAME"
    curl -fsSL --max-time 300 -o "$DESTINATION.partial" "$URL" \
        || fail "could not download $NAME"
    actual="$(shasum -a 256 "$DESTINATION.partial" | cut -d' ' -f1)"
    if [[ "$actual" != "$SHA" ]]; then
        rm -f "$DESTINATION.partial"
        fail "$NAME digest mismatch: expected $SHA, got $actual"
    fi
    mv "$DESTINATION.partial" "$DESTINATION"
    note "verified sha256:${SHA:0:16}"
fi

step "Scaling the Blue Marble to 4096 × 2048"
sips --resampleHeightWidth 2048 4096 \
    --setProperty format jpeg \
    --setProperty formatOptions 85 \
    "$DESTINATION" --out "$IMAGERY_OUT" >/dev/null \
    || fail "could not scale $NAME"
mkdir -p "$APP_RESOURCE_DIR"
cp "$IMAGERY_OUT" "$APP_RESOURCE_IMAGERY" || fail "could not copy the imagery into Resources"
note "copied into Resources/$(basename "$APP_RESOURCE_IMAGERY") ($(du -h "$APP_RESOURCE_IMAGERY" | cut -f1 | tr -d ' '))"
