#!/bin/sh
# 给已使用的 Chromium 浏览器安装当前 App 包的 Native Messaging 清单。
set -eu
cd "$(dirname "$0")/.."
host="$(pwd -P)/.build/Downloader.app/Contents/MacOS/DownloaderHost"
if [ ! -x "$host" ]; then
    echo "未找到下载器宿主，请先运行 ./scripts/make-app.sh" >&2
    exit 1
fi

support="$HOME/Library/Application Support"
installed=0
for browser in 'Google/Chrome' 'Microsoft Edge' 'Arc/User Data' 'BraveSoftware/Brave-Browser'; do
    [ -d "$support/$browser" ] || continue
    dir="$support/$browser/NativeMessagingHosts"
    mkdir -p "$dir"
    temp=$(mktemp "$dir/local.downloader.XXXXXX")
    trap 'rm -f "$temp"' EXIT
    plutil -replace path -string "$host" -o "$temp" - <<'JSON'
{
  "name": "local.downloader",
  "description": "下载器浏览器宿主",
  "path": "",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://fhfcdggihhigpphnfagldelhdcehnkoa/"]
}
JSON
    mv -f "$temp" "$dir/local.downloader.json"
    trap - EXIT
    echo "已安装 $dir/local.downloader.json"
    installed=1
done
if [ "$installed" -eq 0 ]; then
    echo "未发现浏览器数据目录，请先启动一次浏览器再安装。" >&2
    exit 1
fi
