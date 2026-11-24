#!/bin/sh
# 把 swift build 的产物包成 .build/Downloader.app（系统通知、Dock、截图工具都要求正规 app 包）
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

swift build
BIN_DIR=$(swift build --show-bin-path)
APP=.build/Downloader.app

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Downloader" "$APP/Contents/MacOS/Downloader"
cp "$BIN_DIR/DownloaderHost" "$APP/Contents/MacOS/DownloaderHost"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# 浏览器扩展随 App 带上，设置里点「接管」时复制到下载文件夹让用户拖进浏览器
rsync -a --delete --exclude README.md browser/chrome/ "$APP/Contents/Resources/ChromeExtension/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.downloader</string>
    <key>CFBundleName</key><string>Downloader</string>
    <key>CFBundleDisplayName</key><string>下载器</string>
    <key>CFBundleExecutable</key><string>Downloader</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>local.downloader.add</string>
            <key>CFBundleURLSchemes</key><array><string>downloader</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "$APP"
