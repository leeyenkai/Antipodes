#!/usr/bin/env bash
# Builds the iOS app with xcodebuild. Pass a destination to override the default.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require xcodebuild

DESTINATION="${1:-generic/platform=iOS Simulator}"

if [[ ! -f "$APP_RESOURCE_DB" ]]; then
    note "the bundled place database is missing — building it first"
    "$REPO_ROOT/scripts/build-placedb.sh"
fi

step "Building the app for $DESTINATION"
note "derived data: $SCRATCH_PATH/DerivedData"
xcodebuild \
    -project "$REPO_ROOT/Antipodes.xcodeproj" \
    -scheme Antipodes \
    -destination "$DESTINATION" \
    -derivedDataPath "$SCRATCH_PATH/DerivedData" \
    -clonedSourcePackagesDirPath "$SCRATCH_PATH/SourcePackages" \
    CODE_SIGNING_ALLOWED=NO \
    build
