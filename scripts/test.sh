#!/usr/bin/env bash
# Runs the whole test suite. No simulator, no network.
#
# The place-database tests are skipped unless Tools/placedb/out/places.sqlite exists,
# so this builds it first.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require swift
if [[ ! -f "$PLACEDB_OUT" ]]; then
    note "place database not built yet — building it so its tests can run"
    "$REPO_ROOT/scripts/build-placedb.sh" --skip-copy
fi

step "Testing AntipodesKit"
note "scratch: $SCRATCH_PATH"
mkdir -p "$SCRATCH_PATH"
swift test --package-path "$PACKAGE_PATH" --scratch-path "$SCRATCH_PATH" "$@"
