#!/bin/sh
# 由 assets/AppIcon.svg 生成 assets/AppIcon.icns；改了 SVG 后跑一次，产物一起提交
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

ICONSET=$(mktemp -d)/AppIcon.iconset
swift scripts/make-icon.swift assets/AppIcon.svg "$ICONSET"
iconutil -c icns "$ICONSET" -o assets/AppIcon.icns
echo assets/AppIcon.icns
