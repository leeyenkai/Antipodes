#!/usr/bin/env bash
# Renders the app's icon and every concept it was chosen from, in each appearance the
# system can show them in plus a Home Screen-sized copy, and lays them out on one
# contact sheet each and a side-by-side comparison.
#
#     Tools/icon/render.sh [out-dir]       # default: Tools/icon/out
#
# Rendering goes through ictool, the command-line half of Icon Composer that ships
# inside Xcode, so what you see is the system's own Liquid Glass, not an imitation.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$HERE/out}"
ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
[[ -x "$ICTOOL" ]] || { echo "error: ictool not found at $ICTOOL (needs Xcode 26 or later)" >&2; exit 1; }

python3 -I "$HERE/build_icons.py" >/dev/null
python3 -I "$HERE/build_icons.py" --all >/dev/null
mkdir -p "$OUT"

RENDITIONS=(Default Dark ClearLight ClearDark TintedLight TintedDark)
SHEET_ARGS=()
for document in "$HERE/../../App/Antipodes/AppIcon.icon" "$HERE"/out/concepts/*.icon; do
    slug="$(basename "$document" .icon)"
    cells=()
    for rendition in "${RENDITIONS[@]}"; do
        file="$OUT/$slug-$rendition.png"
        "$ICTOOL" "$document" --export-image --output-file "$file" \
            --platform iOS --rendition "$rendition" --width 1024 --height 1024 --scale 1 >/dev/null
        cells+=("$rendition=$file")
    done
    # The size it is mostly seen at: a 60 pt Home Screen icon at 3x.
    small="$OUT/$slug-home.png"
    "$ICTOOL" "$document" --export-image --output-file "$small" \
        --platform iOS --rendition Default --width 60 --height 60 --scale 3 >/dev/null
    cells+=("Home Screen size=$small")
    swift "$HERE/contact_sheet.swift" "$OUT/$slug-sheet.png" 7 220 "${cells[@]}"
    SHEET_ARGS+=("$slug=$OUT/$slug-Default.png" "-=$OUT/$slug-Dark.png" "-=$OUT/$slug-TintedDark.png" "-=$small")
done
swift "$HERE/contact_sheet.swift" "$OUT/comparison.png" 4 300 "${SHEET_ARGS[@]}"
echo "wrote $OUT"
