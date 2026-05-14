#!/bin/bash
# Generate all required iOS app icon sizes from AppIcon-1024.png
# Usage: ./generate_icon_sizes.sh <path-to-appiconset-dir>

ICONSET="${1:-Claw/Assets.xcassets/AppIcon.appiconset}"
SRC="$ICONSET/AppIcon-1024.png"

if [ ! -f "$SRC" ]; then
  echo "Source not found: $SRC"
  exit 1
fi

resize() {
  local px=$1
  local name=$2
  sips -z "$px" "$px" "$SRC" --out "$ICONSET/$name" > /dev/null
  echo "  $name (${px}x${px})"
}

echo "Generating icon sizes from $SRC..."
resize 20   "Icon-20.png"
resize 29   "Icon-29.png"
resize 40   "Icon-40.png"
resize 58   "Icon-58.png"
resize 60   "Icon-60.png"
resize 76   "Icon-76.png"
resize 80   "Icon-80.png"
resize 87   "Icon-87.png"
resize 120  "Icon-120.png"
resize 152  "Icon-152.png"
resize 167  "Icon-167.png"
resize 180  "Icon-180.png"
echo "Done."
