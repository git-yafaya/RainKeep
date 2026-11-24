# Downloader

[中文](README.md)

A macOS download manager (SwiftUI): multi-connection segmented downloads, resume support, takes over downloads from Chrome-family browsers, and custom categories that learn how you sort.

It downloads real files: segmented in parallel when the server allows it, resumes from where it stopped after a pause or a network drop (network errors are retried automatically), and sorts files into subfolders of Downloads by type. Tasks and settings are saved to `~/Library/Application Support/Downloader/state.json` and resume after a restart.

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
- Custom categories: "New Category" at the bottom of the sidebar; right-click a category to add a subcategory (up to three levels), rename or delete it. Drag a task onto a category, or right-click a task and choose "Move to". With "Learn my sorting habits" on, after about 3 manual sorts of similar files, new ones are sorted automatically: file content first (JSON fields, data embedded in PNGs), then source page, Discord channel and file name, then site and extension
- Menu bar icon: check progress, open the main window or quit; while it is on, closing the window keeps downloads running
- ⌘,: settings. General: download folder, concurrent downloads, segments, subfolders, learning, notices, menu bar. Appearance: theme (System / Rainforest / Orange Peel / Gardenia), text size (12–16 px), background image (text color adapts to the image's brightness), language (中文 / English)

## Browser takeover

Works with Chrome, Edge, Arc and Brave:

```bash
./scripts/make-app.sh
```

```bash
./scripts/install-browser-host.sh
```

Then turn on Developer mode on the browser's extensions page and use "Load unpacked" on `browser/chrome/`. See [browser/chrome/README.md](browser/chrome/README.md) (Chinese).

## Layout

- `Sources/DownloaderCore`: UI-free logic (download engine, retry policy, categories, naming, scheduling, formatting)
- `Sources/DownloaderHost`, `browser/chrome`: browser extension and native host
- `Sources/Downloader`: SwiftUI interface
- `prototype/index.html`: HTML prototype of the interface, open it in a browser
- `docs/UI.md`: interface rules (Chinese)
- `assets/AppIcon.svg`: app icon source; after editing, run `./scripts/make-icon.sh` to regenerate `AppIcon.icns`
