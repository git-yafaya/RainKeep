import RainkeepCore
import Foundation
import Testing

private func withSupportDirectory(_ body: (URL) throws -> Void) throws {
    let manager = FileManager.default
    let support = manager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try manager.createDirectory(at: support, withIntermediateDirectories: false)
    defer {
        do { try manager.removeItem(at: support) }
        catch { Issue.record(error) }
    }
    try body(support)
}

@Test func installsBrowserHostsAndUpdatesMovedHost() throws {
    try withSupportDirectory { support in
        let manager = FileManager.default
        let profiles = ["Google/Chrome", "Arc/User Data"].map { support.appending(path: $0) }
        for profile in profiles {
            try manager.createDirectory(at: profile, withIntermediateDirectories: true)
        }
        let host = support.appending(path: "拾雨.app/Contents/MacOS/RainkeepHost")
        let installed = try BrowserHost.install(hostPath: host, support: support)
        #expect(installed.map(\.name) == ["Chrome", "Arc"])
        for path in ["Microsoft Edge", "BraveSoftware/Brave-Browser"] {
            #expect(!manager.fileExists(atPath: support.appending(path: path).path))
        }
        let files = profiles.map { $0.appending(path: "NativeMessagingHosts/com.yafaya.rainkeep.json") }
        let oldDate = Date(timeIntervalSince1970: 1_000_000)
        for file in files {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
            let manifest = try #require(object as? [String: Any])
            #expect(manifest["name"] as? String == "com.yafaya.rainkeep")
            #expect(manifest["description"] as? String == "拾雨浏览器宿主")
            #expect(manifest["type"] as? String == "stdio")
            #expect(manifest["path"] as? String == host.path)
            #expect(manifest["allowed_origins"] as? [String] == ["chrome-extension://fhfcdggihhigpphnfagldelhdcehnkoa/"])
            try manager.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)
        }

        #expect(try BrowserHost.install(hostPath: host, support: support) == installed)
        for file in files {
            #expect(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == oldDate)
        }
        let moved = support.appending(path: "Moved/RainkeepHost")
        #expect(try BrowserHost.install(hostPath: moved, support: support) == installed)
        for file in files {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
            #expect((object as? [String: Any])?["path"] as? String == moved.path)
        }
    }
}

@Test func installsNoHostsWithoutBrowserData() throws {
    try withSupportDirectory { support in
        let installed = try BrowserHost.install(hostPath: support.appending(path: "RainkeepHost"), support: support)
        let contents = try FileManager.default.contentsOfDirectory(atPath: support.path)
        #expect(installed.isEmpty)
        #expect(contents.isEmpty)
    }
}

@Test func extensionLinkLoadsLatestRecordAndReportsCorruption() throws {
    try withSupportDirectory { support in
        let file = support.appending(path: "Rainkeep/extension.json")
        #expect(ExtensionLink.file(in: support) == file)
        #expect(try ExtensionLink.load(from: support) == nil)
        for browser in ["Google Chrome", nil] {
            let link = ExtensionLink(browser: browser, seen: Date())
            try link.save(to: support)
            #expect(try ExtensionLink.load(from: support) == link)
        }
        try Data("broken".utf8).write(to: file)
        #expect(throws: DecodingError.self) { try ExtensionLink.load(from: support) }
    }
}
