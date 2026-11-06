#!/bin/zsh
# Regenerates Resources/AppIcon.icns and docs/icon.png from scripts/make-icon.swift.
set -euo pipefail
cd "${0:A:h}/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
set=$tmp/AppIcon.iconset
mkdir -p "$set"

swift scripts/make-icon.swift "$tmp/master.png" 1024
for size in 16 32 128 256 512; do
  sips -z $size $size "$tmp/master.png" --out "$set/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$tmp/master.png" --out "$set/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p Resources docs
iconutil -c icns "$set" -o Resources/AppIcon.icns
sips -z 256 256 "$tmp/master.png" --out docs/icon.png >/dev/null
echo "Wrote Resources/AppIcon.icns and docs/icon.png"
