# 下载器

[English](README_en.md)

一个 macOS 下载器（SwiftUI）：多线程分段、断点续传，下完按类型放进下载文件夹的子目录。

目前完成的是界面：任务列表用模拟数据跑进度，还不会真正下载。

## 前置依赖

- macOS 14 及以上
- Xcode（SwiftUI 宏需要 Xcode 的工具链，只有命令行工具编译不了）

## 快速开始

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run Downloader
```

已经用 `sudo xcode-select -s /Applications/Xcode.app` 切换过的，直接 `swift run Downloader` 即可。也可以 `open Package.swift` 用 Xcode 打开。

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

- `Sources/DownloaderCore`：不依赖界面的逻辑（分类、命名、调度、格式化）
- `Sources/Downloader`：SwiftUI 界面
- `prototype/index.html`：界面的 HTML 原型，浏览器直接打开
- `docs/UI.md`：界面规则
