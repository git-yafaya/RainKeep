// swift-tools-version: 6.0
// 工程结构：DownloaderCore 放不依赖界面的逻辑（以后的下载引擎也放这里），Downloader 是 SwiftUI 应用
import PackageDescription

let package = Package(
    name: "Downloader",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DownloaderCore"),
        .executableTarget(name: "Downloader", dependencies: ["DownloaderCore"]),
        .executableTarget(name: "DownloaderHost", dependencies: ["DownloaderCore"]),
        .testTarget(name: "DownloaderCoreTests", dependencies: ["DownloaderCore"]),
    ]
)
