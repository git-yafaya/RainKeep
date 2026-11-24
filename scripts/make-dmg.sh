#!/bin/sh
# 打 release 版 App，再装进 dist/Rainkeep-<版本>.dmg（打开后把拾雨拖进「应用程序」）
set -eu
cd "$(dirname "$0")/.."

APP=$(CONFIG=release ./scripts/make-app.sh | tail -1)
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="dist/Rainkeep-$VERSION.dmg"

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir -p dist
hdiutil create -volname "拾雨" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
rm -r "$STAGE" # mktemp 建的临时目录，只装着刚复制的副本

echo "$DMG"
