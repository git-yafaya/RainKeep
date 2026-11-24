#!/bin/sh
# 由 assets/AppIcon.svg 生成 assets/AppIcon.icns 和浏览器扩展的图标；改了 SVG 后跑一次，产物一起提交
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

ICONSET=$(mktemp -d)/AppIcon.iconset
swift scripts/make-icon.swift assets/AppIcon.svg "$ICONSET"
iconutil -c icns "$ICONSET" -o assets/AppIcon.icns
mkdir -p browser/chrome/icons
for size in 16 32 128; do cp "$ICONSET/icon_${size}x${size}.png" "browser/chrome/icons/$size.png"; done
cp "$ICONSET/icon_32x32@2x.png" browser/chrome/icons/64.png
echo assets/AppIcon.icns browser/chrome/icons
