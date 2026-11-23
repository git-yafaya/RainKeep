# 浏览器下载接管

1. 先启动一次要使用的浏览器。然后在项目根目录依次执行 `./scripts/make-app.sh` 和 `./scripts/install-browser-host.sh`。
2. 打开浏览器的扩展程序管理页（Chrome 和 Arc 可输入 `chrome://extensions`，Edge 用 `edge://extensions`，Brave 用 `brave://extensions`）。打开「开发者模式」，点「加载已解压的扩展程序」，选择本目录 `browser/chrome/`。
3. 核对扩展 ID 为 `fhfcdggihhigpphnfagldelhdcehnkoa`。工具栏里的「接管下载」默认开启，关闭后由浏览器直接下载。

宿主清单指向当前项目下的 `.build/Downloader.app`。移动项目后请重新运行安装脚本。App 侧需注册 `downloader://add`，用 `BrowserRequest.parse(_:)` 接收请求，并把 `headers` 传给 `DownloadJob`。

仅接管 HTTP(S) 下载。宿主失败时浏览器重新请求原链接。依赖 POST 正文或只能访问一次的链接可能无法重放。宿主在本机通过 URL 传递站点 Cookie，请避免记录或分享完整的 scheme URL。

在项目根目录可用一条测试消息检查宿主，dry-run 会跳过启动 App。输出应以 `0b 00 00 00` 开头，后面是 `{"ok":true}`。

```sh
printf '\035\000\000\000%s' '{"url":"https://example.org"}' | DOWNLOADER_HOST_DRY_RUN=1 .build/Downloader.app/Contents/MacOS/DownloaderHost | hexdump -C
```
