// 检查更新：解析 GitHub 发布信息、比较版本号
import Foundation
import Testing
@testable import RainkeepCore

@Test func parsesLatestRelease() throws {
    let json = #"""
    { "tag_name": "v1.1", "html_url": "https://github.com/git-yafaya/RainKeep/releases/tag/v1.1",
      "assets": [ { "name": "notes.txt", "browser_download_url": "https://example.com/notes.txt" },
                  { "name": "Rainkeep-1.1.dmg", "browser_download_url": "https://example.com/Rainkeep-1.1.dmg" } ] }
    """#
    let release = try UpdateCheck.parse(Data(json.utf8))
    #expect(release.version == "1.1")
    #expect(release.installer?.lastPathComponent == "Rainkeep-1.1.dmg")

    let bare = try UpdateCheck.parse(Data(#"{ "tag_name": "2.0", "html_url": "https://x.com", "assets": [] }"#.utf8))
    #expect(bare.version == "2.0")
    #expect(bare.installer == nil)
}

@Test func comparesVersionsNumerically() {
    #expect(UpdateCheck.isNewer("1.1", than: "1.0"))
    #expect(UpdateCheck.isNewer("1.10", than: "1.9"))
    #expect(UpdateCheck.isNewer("1.0.1", than: "1.0"))
    #expect(!UpdateCheck.isNewer("1.0.0", than: "1.0"))
    #expect(!UpdateCheck.isNewer("0.9", than: "1.0"))
}
