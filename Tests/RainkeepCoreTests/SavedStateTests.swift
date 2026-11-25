// 存盘兼容测试：1.0 起 state.json 格式固定，改字段时这里会先报错
import Foundation
import Testing
@testable import RainkeepCore

/// 1.0 写出的 state.json 原样冻结在这里，不要改它；格式变了就加新样本，不改旧样本
private let state10 = #"""
{
  "categories" : { "items" : [ { "id" : "11111111-1111-1111-1111-111111111111", "name" : "世界书" } ] },
  "items" : [
    {
      "destination" : "file:///Users/demo/Downloads/%E5%8E%8B%E7%BC%A9%E5%8C%85/big.zip",
      "id" : "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
      "message" : "网络中断，正在重试",
      "name" : "big.zip", "received" : 400, "size" : 1000, "speed" : 123,
      "status" : "downloading", "url" : "https://example.com/big.zip"
    },
    {
      "id" : "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
      "message" : "服务器返回 404",
      "name" : "bad.mp4", "received" : 0, "size" : 0, "speed" : 0,
      "status" : "failed", "url" : "https://example.com/bad.mp4"
    },
    {
      "autoSorted" : true,
      "destination" : "file:///Users/demo/Downloads/%E4%B8%96%E7%95%8C%E4%B9%A6/card.json",
      "features" : [ "ext:json", "site:example.com" ],
      "group" : "11111111-1111-1111-1111-111111111111",
      "id" : "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC",
      "name" : "card.json", "received" : 10, "size" : 10, "speed" : 0,
      "status" : "completed", "url" : "https://example.com/card.json"
    }
  ],
  "learner" : {
    "votes" : { "ext:json" : [ "11111111-1111-1111-1111-111111111111", { "count" : 1, "updated" : 800000000 } ] }
  },
  "settings" : {
    "classify" : true, "downloadDir" : "file:///Users/demo/Downloads", "language" : "en", "learn" : true,
    "maxActive" : 5, "menuBar" : true, "notify" : true, "textSize" : 15, "theme" : "gardenia", "threads" : 8
  }
}
"""#

@Test func restoresState10() throws {
    let state = try SavedState.restore(from: Data(state10.utf8))
    #expect(state.settings.downloadDir.path == "/Users/demo/Downloads")
    #expect(state.settings.maxActive == 5)
    #expect(state.settings.threads == 8)
    #expect(state.settings.theme == .gardenia)
    #expect(state.settings.textSize == 15)
    #expect(state.settings.language == .en)

    let group = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    #expect(state.categories?[group]?.name == "世界书")
    #expect(state.learner != nil)

    let (running, failed, done) = (state.items[0], state.items[1], state.items[2])
    // 上次没下完的重新排队，速度和重试提示清掉
    #expect(running.status == .queued)
    #expect(running.speed == 0)
    #expect(running.message == nil)
    #expect(running.received == 400)
    #expect(running.destination?.path == "/Users/demo/Downloads/压缩包/big.zip")
    // 失败原因要留着给用户看
    #expect(failed.status == .failed)
    #expect(failed.message == "服务器返回 404")
    #expect(done.status == .completed)
    #expect(done.group == group)
    #expect(done.features == ["ext:json", "site:example.com"])
    #expect(done.autoSorted == true)
}

/// 1.0 之前的存盘：没有分类和习惯，设置缺字段，字号还是旧的 fontSize
@Test func restoresPre10State() throws {
    let json = #"{ "items" : [], "settings" : { "maxActive" : 2, "fontSize" : "large" } }"#
    let state = try SavedState.restore(from: Data(json.utf8))
    #expect(state.categories == nil)
    #expect(state.learner == nil)
    #expect(state.settings.maxActive == 2)
    #expect(state.settings.textSize == TextSize.base)
    #expect(state.settings.theme == .system)
    #expect(state.settings.notify)
}

@Test func savedStateRoundTrips() throws {
    let original = try SavedState.restore(from: Data(state10.utf8))
    let again = try SavedState.restore(from: original.encoded())
    #expect(again.settings == original.settings)
    #expect(again.categories == original.categories)
    #expect(again.learner == original.learner)
    #expect(again.items.map(\.id) == original.items.map(\.id))
}
