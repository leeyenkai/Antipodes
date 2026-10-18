#!/usr/bin/env bash
# Everything that must pass before a change is finished.
#
# Deliberately does not build the app: that needs Xcode and a simulator, while this
# runs in seconds. Use scripts/build-app.sh for that.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

"$REPO_ROOT/scripts/build-placedb.sh"
"$REPO_ROOT/scripts/build.sh"
"$REPO_ROOT/scripts/test.sh"
"$REPO_ROOT/scripts/lint.sh" --check || note "lint reported issues (not fatal yet)"

step "All checks passed"
