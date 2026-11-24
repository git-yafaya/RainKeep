#!/bin/sh
# 把 swift build 的产物包成 .build/Rainkeep.app（拾雨；系统通知、Dock、截图工具都要求正规 app 包）
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

CONFIG="${CONFIG:-debug}"
swift build -c "$CONFIG"
BIN_DIR=$(swift build -c "$CONFIG" --show-bin-path)
APP=.build/Rainkeep.app

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Rainkeep" "$APP/Contents/MacOS/Rainkeep"
cp "$BIN_DIR/RainkeepHost" "$APP/Contents/MacOS/RainkeepHost"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# 浏览器扩展随 App 带上，设置里点「接管」时复制到下载文件夹让用户拖进浏览器
rsync -a --delete --exclude README.md browser/chrome/ "$APP/Contents/Resources/ChromeExtension/"
# 访达、Dock、菜单栏里的名字跟系统语言：中文「拾雨」，其他 Rainkeep
mkdir -p "$APP/Contents/Resources/zh-Hans.lproj" "$APP/Contents/Resources/en.lproj"
printf 'CFBundleName = "拾雨";\nCFBundleDisplayName = "拾雨";\n' > "$APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
printf 'CFBundleName = "Rainkeep";\nCFBundleDisplayName = "Rainkeep";\n' > "$APP/Contents/Resources/en.lproj/InfoPlist.strings"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.yafaya.rainkeep</string>
    <key>CFBundleName</key><string>Rainkeep</string>
    <key>CFBundleDisplayName</key><string>Rainkeep</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
    <key>LSHasLocalizedDisplayName</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 yafaya · MIT License</string>
    <key>CFBundleExecutable</key><string>Rainkeep</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>com.yafaya.rainkeep.add</string>
            <key>CFBundleURLSchemes</key><array><string>rainkeep</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST
# 改过包内文件后签名就失效了，重新做临时签名，Apple 芯片上才能打开
codesign --force --deep --sign - "$APP"

echo "$APP"
