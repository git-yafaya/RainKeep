// swift-tools-version: 6.0
// 工程结构：RainkeepCore 放不依赖界面的逻辑，Rainkeep 是 SwiftUI 应用，RainkeepHost 是浏览器扩展的本机宿主
import PackageDescription

let package = Package(
    name: "Rainkeep",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "RainkeepCore"),
        .executableTarget(name: "Rainkeep", dependencies: ["RainkeepCore"]),
        .executableTarget(name: "RainkeepHost", dependencies: ["RainkeepCore"]),
        .testTarget(name: "RainkeepCoreTests", dependencies: ["RainkeepCore"]),
    ]
)
