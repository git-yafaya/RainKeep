# 拾雨 / Rainkeep

macOS 下载器（SwiftUI，macOS 14+）：断点续传、多线程分段、按习惯自动分类、接管浏览器下载。作者 yafaya，MIT。
怎么跑、目录结构见 [README.md](README.md)；界面规则以 [docs/UI.md](docs/UI.md) 为准。本文件只记接手时容易踩的坑。

## 构建与测试

`xcode-select` 可能还指向 CommandLineTools（没有 SwiftUI 宏插件），所有 swift 命令都加上 Xcode 工具链：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./scripts/make-app.sh && open .build/Rainkeep.app   # 调试版 .app，脚本内已设好 DEVELOPER_DIR
./scripts/make-dmg.sh                                # release 版 → dist/Rainkeep-<版本>.dmg
```

- 系统通知、浏览器宿主注册都要正规 .app 包，用 `swift run` 看不到这些功能。
- 改完界面要真跑 `.app` 验证；改 `RainkeepCore` 要跑 `swift test`。

## 工作流

- 新界面先在 `prototype/index.html` 画（照 Mac 原生控件画），用户确认后再搬到 SwiftUI；改了界面规则同步 `docs/UI.md` 和原型。
- 已发布 1.0：下面的固定标识和 `state.json` 数据格式定下来了。数据格式只加可选字段，改动要能读旧数据，不能读就写迁移。
- 不主动加功能，等用户点名。
- 注释、commit message 用中文；commit 用 Conventional Commits 前缀（feat/fix/docs/refactor/chore）。

## 别踩的坑

- **`App.body` 里不能读 `@Observable` 状态**，否则切主题、语言时会递归崩溃。菜单命令和菜单栏图标各自放在独立的 `Commands`/`Scene` 结构里读（见 `RainkeepApp.swift`）。
- Swift 6 严格并发：`DownloadStore` 在主线程，引擎回调要切回主线程再改状态。
- 固定标识，改了要一起改：bundle id 和宿主名 `com.yafaya.rainkeep`、URL scheme `rainkeep://`、数据目录 `~/Library/Application Support/Rainkeep/`。
- 扩展 ID `fhfcdggihhigpphnfagldelhdcehnkoa` 由 `browser/chrome/manifest.json` 的 `key` 决定，宿主清单只放行这个 ID；**不要改 `key`**，否则已装的扩展连不上。
- 浏览器宿主清单每次启动由 App 重写（`BrowserHost.install`），指向当前 `.app` 里的 `RainkeepHost`；挪了 App 位置重启一次即可。
- 扩展通过设置里的「接管」复制到 `~/Downloads/拾雨扩展.bundle`（`.bundle` 让访达把它当一个文件，防止用户拖错里面的文件），浏览器从那里以未打包扩展加载。
- 分类学习（`Categories.swift`）：分层加权投票 + 60 天半衰期，层级 [json, png] → [path, page, word] → [site, ext]。添加时按网址特征建议，下载完按文件内容（`ContentFingerprint`）再归一次。**用户手动指定的分类永远不覆盖。**
- 改图标只改 `assets/AppIcon.svg`，跑 `./scripts/make-icon.sh` 同时生成 `.icns` 和扩展图标，产物一起提交。

## 发版

1. 改 `scripts/make-app.sh` 里的 `CFBundleShortVersionString` 和 `CFBundleVersion`
2. `./scripts/make-dmg.sh`
3. `gh release create v<版本> dist/Rainkeep-<版本>.dmg`

App 只做了临时签名、没有公证，别的 Mac 首次打开要在「隐私与安全性」里点「仍要打开」。`dist/`、`*.dmg` 已在 `.gitignore`，不进仓库。
