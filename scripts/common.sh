#!/usr/bin/env bash
# Shared settings for the repository scripts. Sourced, not run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_PATH="$REPO_ROOT/AntipodesKit"
PLACEDB_OUT="$REPO_ROOT/Tools/placedb/out/places.sqlite"
APP_RESOURCE_DB="$REPO_ROOT/App/Antipodes/Resources/places.sqlite"

# Build products are kept outside the repository on purpose.
#
# This checkout can sit in an iCloud-synced folder (Desktop, Documents), and the file
# provider stamps com.apple.FinderInfo onto directories it syncs. codesign refuses to
# sign a bundle carrying it — "resource fork, Finder information, or similar detritus
# not allowed" — so a .build inside the repository breaks every test run. Building to
# ~/Library/Caches sidesteps it. Override with ANTIPODES_SCRATCH if you prefer.
SCRATCH_PATH="${ANTIPODES_SCRATCH:-$HOME/Library/Caches/Antipodes/swiftpm}"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
note() { printf '    %s\n' "$1"; }
fail() { printf '\033[31merror: %s\033[0m\n' "$1" >&2; exit 1; }

require() {
    command -v "$1" >/dev/null 2>&1 || fail "$1 is required but not installed"
}
