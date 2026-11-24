// Chrome 系浏览器的本机宿主注册（Native Messaging 清单）和扩展最近一次连上的记录
import Foundation

public struct ChromiumBrowser: Sendable, Equatable {
    public let name: String
    public let bundleID: String
    public let dataPath: String
    public let extensionsPage: URL

    public static let all: [ChromiumBrowser] = [
        .init(name: "Chrome", bundleID: "com.google.Chrome", dataPath: "Google/Chrome",
              extensionsPage: URL(string: "chrome://extensions")!),
        .init(name: "Edge", bundleID: "com.microsoft.edgemac", dataPath: "Microsoft Edge",
              extensionsPage: URL(string: "edge://extensions")!),
        .init(name: "Arc", bundleID: "company.thebrowser.Browser", dataPath: "Arc/User Data",
              extensionsPage: URL(string: "chrome://extensions")!),
        .init(name: "Brave", bundleID: "com.brave.Browser", dataPath: "BraveSoftware/Brave-Browser",
              extensionsPage: URL(string: "brave://extensions")!),
    ]
}

public enum BrowserHost {
    public static let name = "com.yafaya.rainkeep"
    public static let extensionID = "fhfcdggihhigpphnfagldelhdcehnkoa"

    /// 给装过的浏览器写宿主清单，内容没变不重写；返回写好的浏览器
    public static func install(hostPath: URL, support: URL) throws -> [ChromiumBrowser] {
        let manifest = try JSONSerialization.data(withJSONObject: [
            "name": name, "description": "拾雨浏览器宿主", "path": hostPath.path,
            "type": "stdio", "allowed_origins": ["chrome-extension://\(extensionID)/"],
        ], options: [.sortedKeys, .withoutEscapingSlashes])

        var installed: [ChromiumBrowser] = []
        for browser in ChromiumBrowser.all {
            let profile = support.appending(path: browser.dataPath, directoryHint: .isDirectory)
            do {
                guard try profile.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                else { continue }
            } catch CocoaError.fileReadNoSuchFile { continue }

            let directory = profile.appending(path: "NativeMessagingHosts", directoryHint: .isDirectory)
            let file = directory.appending(path: "\(name).json")
            let previous: Data?
            do { previous = try Data(contentsOf: file) }
            catch CocoaError.fileReadNoSuchFile { previous = nil }
            if previous != manifest {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try manifest.write(to: file, options: .atomic)
            }
            installed.append(browser)
        }
        return installed
    }
}

public struct ExtensionLink: Codable, Sendable, Equatable {
    public var browser: String?
    public var seen: Date

    public init(browser: String?, seen: Date) {
        self.browser = browser
        self.seen = seen
    }

    public static func file(in support: URL) -> URL {
        support.appending(path: "Rainkeep/extension.json")
    }

    public static func load(from support: URL) throws -> ExtensionLink? {
        let data: Data
        do { data = try Data(contentsOf: file(in: support)) }
        catch CocoaError.fileReadNoSuchFile { return nil }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    public func save(to support: URL) throws {
        let file = Self.file(in: support)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
    }
}
