# 下载器

[English](README_en.md)

一个 macOS 下载器（SwiftUI）：多线程分段、断点续传，下完按类型放进下载文件夹的子目录。

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
- ⌘,：设置（下载位置、同时下载数、每个任务分段、按类型分子文件夹、完成通知）

## 目录

- `Sources/DownloaderCore`：不依赖界面的逻辑（下载引擎、重试策略、分类、命名、调度、格式化）
- `Sources/Downloader`：SwiftUI 界面
- `prototype/index.html`：界面的 HTML 原型，浏览器直接打开
- `docs/UI.md`：界面规则
