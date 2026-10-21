#!/usr/bin/env bash
# Regenerate AppIcon.icns and AppIcon.png from assets/hushswedish-logo.svg
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOGO="$ROOT_DIR/assets/hushswedish-logo.svg"
ASSETS="$ROOT_DIR/HushScribe/Sources/HushScribe/Assets"
WORK="$ASSETS/.icon-build"
ICONSET="$WORK/AppIcon.iconset"

if [[ ! -f "$LOGO" ]]; then
  echo "Missing logo: $LOGO" >&2
  exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK" "$ICONSET"

echo "Rendering 1024×1024 PNG from SVG…"
qlmanage -t -s 1024 -o "$WORK" "$LOGO" >/dev/null 2>&1
MASTER="$WORK/hushswedish-logo.svg.png"
if [[ ! -f "$MASTER" ]]; then
  echo "Quick Look failed to render SVG" >&2
  exit 1
fi

resize() {
  sips -z "$2" "$2" "$MASTER" --out "$ICONSET/$1" >/dev/null
}

resize icon_16x16.png 16
resize icon_16x16@2x.png 32
resize icon_32x32.png 32
resize icon_32x32@2x.png 64
resize icon_128x128.png 128
resize icon_128x128@2x.png 256
resize icon_256x256.png 256
resize icon_256x256@2x.png 512
resize icon_512x512.png 512
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$ASSETS/AppIcon.icns"
cp "$MASTER" "$ASSETS/AppIcon.png"
rm -rf "$WORK"

echo "Wrote $ASSETS/AppIcon.icns and AppIcon.png"
