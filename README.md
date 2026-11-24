# 下载器

[English](README_en.md)

一个 macOS 下载器（SwiftUI）：多线程分段、断点续传，能接管 Chrome 系浏览器的下载，支持自定义分类并学习你的归类习惯。

已经能真正下载：服务器支持时分段并发，暂停或断网后从断点续传（网络类错误自动重试），按类型放进「下载」下的子文件夹。任务列表和设置存在 `~/Library/Application Support/Downloader/state.json`，重启后自动续传。

## 前置依赖

- macOS 14 及以上
- Xcode（SwiftUI 宏需要 Xcode 的工具链，只有命令行工具编译不了）

## 快速开始

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run Downloader
```

已经用 `sudo xcode-select -s /Applications/Xcode.app` 切换过的，直接 `swift run Downloader` 即可。也可以 `open Package.swift` 用 Xcode 打开。

打包成 `.app`（有 Dock 图标和正式的应用身份）：

```bash
./scripts/make-app.sh && open .build/Downloader.app
```

运行测试：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## 使用

- ⌘N 或工具栏 `+`：粘贴链接（每行一个），⌘Enter 开始下载；也可以把链接直接拖进窗口
- 左侧栏按类型筛选，工具栏切换 全部 / 进行中 / 已完成
- 鼠标移到任务上：暂停、继续、重试、移除
- 自定义分类：侧栏底部「新建分类」，右键分类可建子分类（最多三级）、改名、删除；把任务拖到分类上，或右键任务「移到分类」。开了「学习我的分类习惯」后，同类文件手动归 3 次左右就会自动归：先看文件内容（JSON 字段、PNG 里嵌的数据，能分开世界书、预设、角色卡），再看来源页面、Discord 频道、文件名，最后看网站和扩展名
- 菜单栏图标：看下载进度、打开主窗口或退出；开着时关窗口不退出，下载继续
- ⌘,：设置。常规页是下载位置、同时下载数、分段、子文件夹、学习、通知、菜单栏；外观页是主题（跟随系统 / 热带雨林 / 初夏橙皮 / 雨后栀子）、字号（12–16 px）、背景图（字色会按图片明暗自动调）、语言（中文 / English）

## 接管浏览器下载

支持 Chrome、Edge、Arc、Brave：

```bash
./scripts/make-app.sh
```

```bash
./scripts/install-browser-host.sh
```

然后在浏览器扩展页打开「开发者模式」，「加载已解压的扩展程序」选 `browser/chrome/`。详见 [browser/chrome/README.md](browser/chrome/README.md)。

## 目录

- `Sources/DownloaderCore`：不依赖界面的逻辑（下载引擎、重试策略、分类、命名、调度、格式化）
- `Sources/Downloader`：SwiftUI 界面
- `Sources/DownloaderHost`、`browser/chrome`：浏览器扩展和本机宿主
- `prototype/index.html`：界面的 HTML 原型，浏览器直接打开
- `docs/UI.md`：界面规则
- `assets/AppIcon.svg`：应用图标源文件；改完跑 `./scripts/make-icon.sh` 重新生成 `AppIcon.icns`
