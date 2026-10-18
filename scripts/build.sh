#!/usr/bin/env bash
# Builds the AntipodesKit package.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require swift
step "Building AntipodesKit"
note "scratch: $SCRATCH_PATH"
mkdir -p "$SCRATCH_PATH"
swift build --package-path "$PACKAGE_PATH" --scratch-path "$SCRATCH_PATH" "$@"
