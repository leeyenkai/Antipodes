#!/usr/bin/env bash
# Downloads the open data the place database is built from.
#
# This and scripts/fetch-borders.sh are the only scripts in the repository that need a
# network connection. The app never does, and neither does a rebuild: everything lands
# in Tools/placedb/vendor/ and build_placedb.py reads only from there.
#
# Pass --refresh to re-download, or --cities <dataset> to fetch a different GeoNames
# populated-place extract (Q-5).
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require python3

step "Fetching place-database sources"
python3 -I "$REPO_ROOT/Tools/placedb/fetch_sources.py" "$@"
