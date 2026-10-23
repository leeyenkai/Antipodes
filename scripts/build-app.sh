#!/usr/bin/env bash
# Builds the iOS app with xcodebuild. Pass a destination to override the default.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require xcodebuild

DESTINATION="${1:-generic/platform=iOS Simulator}"
shift || true

if [[ ! -f "$APP_RESOURCE_DB" ]]; then
    note "the bundled place database is missing — building it first"
    "$REPO_ROOT/scripts/build-placedb.sh"
fi
if [[ ! -f "$APP_RESOURCE_DIR/borders-50m.antborders" || ! -f "$APP_RESOURCE_DIR/borders-110m.antborders" ]]; then
    note "the bundled country outlines are missing — building them first"
    "$REPO_ROOT/scripts/build-borders.sh"
fi
if [[ ! -f "$APP_RESOURCE_IMAGERY" ]]; then
    note "the satellite picture is missing — fetching and scaling it first"
    "$REPO_ROOT/scripts/fetch-imagery.sh"
fi
# The route pack is optional and its fetch takes hours, so it is built only from a
# cache that is already there.
if [[ ! -f "$APP_RESOURCE_PACK" ]]; then
    if [[ -f "$OSMPACK_DIR/vendor/osm/manifest.json" ]]; then
        note "the route pack is missing — building it from the cached OpenStreetMap data"
        "$REPO_ROOT/scripts/build-osmpack.sh"
    else
        note "no route pack: trails, lifts and route shapes are left out (scripts/fetch-osmpack.sh)"
    fi
fi

# The simulator takes an ad-hoc signature, which is what carries the app-group
# entitlement the widgets read through. A device or Mac build needs a team, so
# those are built unsigned here; archive from Xcode to ship.
if [[ "$DESTINATION" == *Simulator* ]]; then
    SIGNING=(CODE_SIGN_IDENTITY=-)
else
    SIGNING=(CODE_SIGNING_ALLOWED=NO)
fi

step "Building the app for $DESTINATION"
note "derived data: $SCRATCH_PATH/DerivedData"
xcodebuild \
    -project "$REPO_ROOT/Antipodes.xcodeproj" \
    -scheme Antipodes \
    -destination "$DESTINATION" \
    -derivedDataPath "$SCRATCH_PATH/DerivedData" \
    -clonedSourcePackagesDirPath "$SCRATCH_PATH/SourcePackages" \
    "${SIGNING[@]}" \
    "$@" \
    build
