# Downloader

[中文](README.md)

A macOS download manager (SwiftUI): multi-connection segmented downloads, resume support, and finished files sorted into subfolders of your Downloads folder by type.

Current state: the interface is done; the task list runs on simulated progress and does not download real files yet.

## Requirements

- macOS 14 or later
- Xcode (SwiftUI macros need the Xcode toolchain; Command Line Tools alone cannot build it)

## Quick start

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run Downloader
```

If you have switched with `sudo xcode-select -s /Applications/Xcode.app`, plain `swift run Downloader` works. You can also `open Package.swift` in Xcode.

Build a `.app` bundle (Dock icon and a proper app identity):

```bash
./scripts/make-app.sh && open .build/Downloader.app
```

Run tests:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Usage

- ⌘N or the toolbar `+`: paste links (one per line), ⌘Enter to start; or drag links into the window
- Sidebar filters by type; the toolbar switches All / In progress / Done
- Hover a task to pause, resume, retry or remove it
- ⌘,: settings (download folder, concurrent downloads, segments per task, sort into subfolders, completion notice)

## Layout

- `Sources/DownloaderCore`: UI-free logic (categories, naming, scheduling, formatting)
- `Sources/Downloader`: SwiftUI interface
- `prototype/index.html`: HTML prototype of the interface, open it in a browser
- `docs/UI.md`: interface rules (Chinese)
