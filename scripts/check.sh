#!/usr/bin/env bash
# Everything that must pass before a change is finished.
#
# Builds the data, the package and its tests, lints, and — where Xcode is installed —
# builds the app for the iOS Simulator and for the Mac, so a change that compiles only
# on one platform is caught here. Set ANTIPODES_SKIP_APP=1 to leave the app builds out
# for a faster loop.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

"$REPO_ROOT/scripts/build-placedb.sh"
"$REPO_ROOT/scripts/build-borders.sh"
# The route pack only where its OpenStreetMap cache has been fetched (D-36).
if [[ -f "$OSMPACK_DIR/vendor/osm/manifest.json" ]]; then
    "$REPO_ROOT/scripts/build-osmpack.sh"
fi
"$REPO_ROOT/scripts/build.sh"
"$REPO_ROOT/scripts/test.sh"
"$REPO_ROOT/scripts/lint.sh" --check

if [[ "${ANTIPODES_SKIP_APP:-0}" != "1" ]] && command -v xcodebuild >/dev/null 2>&1; then
    "$REPO_ROOT/scripts/build-app.sh" "generic/platform=iOS Simulator" -quiet
    "$REPO_ROOT/scripts/build-app.sh" "generic/platform=macOS" -quiet
else
    note "skipping the app builds"
fi

step "All checks passed"
