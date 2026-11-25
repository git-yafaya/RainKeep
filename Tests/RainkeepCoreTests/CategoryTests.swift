// 自定义分类树、习惯学习、背景图明暗、英文文案测试
import CoreGraphics
import Foundation
import Testing
@testable import RainkeepCore

// #expect / #require 宏里不能调 mutating 方法，所以先存结果再断言
@Test func treeLimitsDepthAndRemovesSubtree() throws {
    var tree = CategoryTree()
    let workAdded = tree.add("工作", parent: nil)
    let work = try #require(workAdded)
    let projectAdded = tree.add("项目 A", parent: work.id)
    let project = try #require(projectAdded)
    let designAdded = tree.add("设计稿", parent: project.id)
    let design = try #require(designAdded)
    let tooDeep = tree.add("第四级", parent: design.id)
    #expect(tooDeep == nil)
    #expect(tree.path(of: design.id).map(\.name) == ["工作", "项目 A", "设计稿"])
    #expect(tree.subtree(of: work.id) == [work.id, project.id, design.id])

    let removed = tree.remove(project.id)
    #expect(removed == [project.id, design.id])
    #expect(tree.items.map(\.name) == ["工作"])
}

@Test func treeRejectsPathLikeNames() {
    var tree = CategoryTree()
    let blank = tree.add("  ", parent: nil)
    let slash = tree.add("a/b", parent: nil)
    #expect(blank == nil && slash == nil)
    guard let study = tree.add(" 学习 ", parent: nil) else { Issue.record("没建出来"); return }
    #expect(study.name == "学习")
    let dots = tree.rename(study.id, to: "..")
    let renamed = tree.rename(study.id, to: "读书")
    #expect(!dots && renamed)
    #expect(tree[study.id]?.name == "读书")
}

@Test func learnerSuggestsAfterThreshold() throws {
    var tree = CategoryTree()
    let workAdded = tree.add("工作", parent: nil)
    let work = try #require(workAdded)
    let otherAdded = tree.add("其他", parent: nil)
    let other = try #require(otherAdded)
    var learner = CategoryLearner()
    let url = URL(string: "https://www.example.com/a.pdf")!
    func keys(_ link: URL?, _ name: String) -> [String] { LearnFeatures.make(url: link, referrer: nil, fileName: name) }

    learner.record(keys(url, "a.pdf"), to: work.id)
    learner.record(keys(url, "b.pdf"), to: work.id)
    #expect(learner.suggest(keys(url, "c.pdf"), in: tree) == nil)
    learner.record(keys(url, "c.pdf"), to: work.id)
    #expect(learner.suggest(keys(URL(string: "https://example.com/x.zip"), "x.zip"), in: tree)?.category == work.id)
    #expect(learner.suggest(keys(URL(string: "https://other.org/y.pdf"), "y.pdf"), in: tree)?.category == work.id)

    // 一次误归后仍有四分之三的票；已删除的分类不参与打分。
    learner.record(keys(url, "d.pdf"), to: other.id)
    #expect(learner.suggest(keys(url, "e.pdf"), in: tree)?.category == work.id)
    tree.remove(work.id)
    #expect(learner.suggest(keys(URL(string: "https://none.io/f.pdf"), "f.pdf"), in: tree) == nil)
}

@Test func imageToneSeparatesLightAndDark() throws {
    func solid(_ white: CGFloat) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: white, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return try #require(context.makeImage())
    }
    #expect(ImageTone.isBright(try solid(0.95)))
    #expect(!ImageTone.isBright(try solid(0.1)))
}

@Test func englishSummary() {
    var item = DownloadItem(name: "a.mp4", size: 2048 * 1024 * 1024, received: 1024 * 1024 * 1024, status: .paused)
    #expect(Format.summary(item, .en) == "Paused · 1.0 GB / 2.0 GB")
    item.status = .completed
    #expect(Format.summary(item, .en) == "2.0 GB · Videos")
    #expect(Format.summary(item, .en, groupName: "Work") == "2.0 GB · Work")
    #expect(Format.eta(90, .en) == "2 min")
}

@Test func votesDecayRetractAndForget() throws {
    var tree = CategoryTree()
    let a = tree.add("世界书", parent: nil)!.id
    let b = tree.add("预设", parent: nil)!.id
    let now = Date.now
    let keys = ["ext:json"]
    var learner = CategoryLearner()
    for _ in 0..<5 { learner.record(keys, to: a, now: now) }
    learner.record(keys, to: b, now: now)
    #expect(learner.suggest(keys, in: tree, now: now)?.category == a)
    learner.retract(keys, from: a, now: now)
    #expect(learner.suggest(keys, in: tree, now: now.addingTimeInterval(61 * 86_400)) == nil)
    for _ in 0..<2 { learner.retract(keys, from: a, now: now) }
    #expect(learner.suggest(keys, in: tree, now: now) == nil)
    for _ in 0..<4 { learner.record(keys, to: b, now: now) }
    #expect(learner.suggest(keys, in: tree, now: now)?.category == b)
    learner.forget([b])
    #expect(learner.suggest(keys, in: tree, now: now) == nil)
}

@Test func discordChannelAndFilenameFeatures() throws {
    func keys(_ message: Int) -> [String] {
        LearnFeatures.make(url: URL(string: "https://cdn.discordapp.com/attachments/123/\(message)/x.json"),
                           referrer: URL(string: "https://www.discordapp.com/chat"),
                           fileName: "角色世界书-Été_V2-123-été.JSON")
    }
    let features = keys(456)
    #expect(features == keys(789))
    #expect(Set(features) == ["page:discordapp.com", "ext:json", "path:discordapp.com/attachments/123",
                               "word:角色", "word:色世", "word:世界", "word:界书", "word:été", "word:v2"])
    let short = LearnFeatures.make(url: URL(string: "https://dl.example.org/channel/x.json"),
                                   referrer: nil, fileName: "x.json")
    #expect(short == ["site:example.org", "ext:json"])
}

private func withFingerprintDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    do {
        try body(directory)
    } catch {
        try FileManager.default.removeItem(at: directory)
        throw error
    }
    try FileManager.default.removeItem(at: directory)
}

@Test func jsonContentSeparatesDownloads() throws {
    try withFingerprintDirectory { directory in
        var tree = CategoryTree()
        var learner = CategoryLearner()
        var examples: [(URL, UUID, String)] = []
        for (index, sample) in [("世界书", "Entries"), ("预设", "Prompts"), ("脚本", "Script")].enumerated() {
            let file = directory.appendingPathComponent("\(index).JSON")
            try Data("{\"\(sample.1)\":{\"nested\":true}}".utf8).write(to: file)
            let category = tree.add(sample.0, parent: nil)!.id
            let content = try ContentFingerprint.features(of: file)
            #expect(content == ["json:" + sample.1.lowercased()])
            examples.append((file, category, "json:" + sample.1.lowercased()))
            let keys = LearnFeatures.make(url: nil, referrer: nil, fileName: file.lastPathComponent, content: content)
            for _ in 0..<3 { learner.record(keys, to: category) }
        }
        // 两类共享扩展名时，加入各自的内容特征后占票 75%。
        var twoKinds = learner
        twoKinds.forget([examples[2].1])
        for (file, category, _) in examples.prefix(2) {
            let content = try ContentFingerprint.features(of: file)
            let keys = LearnFeatures.make(url: nil, referrer: nil, fileName: file.lastPathComponent, content: content)
            #expect(twoKinds.suggest(keys, in: tree)?.category == category)
        }
        #expect(learner.suggest(["ext:json"], in: tree) == nil)
        for (file, category, reason) in examples {
            let content = try ContentFingerprint.features(of: file)
            let suggestion = learner.suggest(content, in: tree)
            #expect(suggestion?.category == category)
            #expect(suggestion?.reason == reason)
        }
        let file = directory.appendingPathComponent("limits.json")
        try Data("[]".utf8).write(to: file)
        #expect(try ContentFingerprint.features(of: file).isEmpty)
        try Data(repeating: 32, count: 5 * 1024 * 1024 + 1).write(to: file)
        #expect(try ContentFingerprint.features(of: file).isEmpty)
        let many = Dictionary(uniqueKeysWithValues: (0..<40).map { ("key\($0)", 1) })
        try JSONEncoder().encode(many).write(to: file)
        #expect(try ContentFingerprint.features(of: file).count == 30)
        try Data("{".utf8).write(to: file)
        #expect(throws: (any Error).self) { try ContentFingerprint.features(of: file) }
    }
}

@Test func pngKeywordsAfterImageData() throws {
    func chunk(_ type: String, _ bytes: [UInt8] = []) -> Data {
        var length = UInt32(bytes.count).bigEndian
        return withUnsafeBytes(of: &length) { Data($0) } + Data(type.utf8) + Data(bytes) + Data(count: 4)
    }
    try withFingerprintDirectory { directory in
        let file = directory.appendingPathComponent("card.png")
        let image = Data([137, 80, 78, 71, 13, 10, 26, 10]) + chunk("IHDR", [0,0,0,1,0,0,0,1,8,2,0,0,0])
            + chunk("IDAT", [1, 2, 3])
        try (image + chunk("IEND")).write(to: file)
        #expect(try ContentFingerprint.features(of: file).isEmpty)
        let card = image + chunk("tEXt", Array("Chara\0payload".utf8))
        try (card + chunk("IEND") + chunk("iTXt", Array("ignored\0".utf8))).write(to: file)
        #expect(try ContentFingerprint.features(of: file) == ["png:chara"])
        let extra = chunk("iTXt", Array("ccv3\0".utf8)) + chunk("zTXt", Array("other\0".utf8))
        try (card + extra + Data([255,255,255,255]) + chunk("tEXt")).write(to: file)
        #expect(try ContentFingerprint.features(of: file) == ["png:ccv3", "png:chara", "png:other"])
    }
}

@Test func migratedHabitsRoundTrip() throws {
    var tree = CategoryTree()
    let id = tree.add("旧分类", parent: nil)!.id
    let habit = #"{"category":"\#(id)","count":4}"#
    let data = Data(#"{"habits":{"host:cdn.example.org":\#(habit),"ext:json":\#(habit)}}"#.utf8)
    let learner = try JSONDecoder().decode(CategoryLearner.self, from: data)
    for key in ["site:example.org", "ext:json"] {
        #expect(learner.suggest([key], in: tree)?.category == id)
    }
    #expect(try JSONDecoder().decode(CategoryLearner.self, from: JSONEncoder().encode(learner)) == learner)
}

@Test func contentTierWinsAndGroupSharesItsWeight() {
    var tree = CategoryTree()
    let a = tree.add("世界书", parent: nil)!.id
    let b = tree.add("预设", parent: nil)!.id
    var learner = CategoryLearner()
    let now = Date.now
    // 内容层先判断：来源页票再多也不影响
    let json = (0..<30).map { "json:key\($0)" }
    for _ in 0..<3 { learner.record(json, to: a, now: now) }
    for _ in 0..<10 { learner.record(["page:discord.com"], to: b, now: now) }
    #expect(learner.suggest(json + ["page:discord.com"], in: tree, now: now)?.category == a)

    // 同层里一组特征共用权重：12 个词合起来只顶权重 2，敌不过来源页
    let words = (0..<12).map { "word:w\($0)" }
    var fresh = CategoryLearner()
    for _ in 0..<3 { fresh.record(words, to: a, now: now) }
    for _ in 0..<4 { fresh.record(["page:discord.com"], to: b, now: now) }
    let mixed = words + ["page:discord.com"]
    #expect(fresh.suggest(mixed, in: tree, now: now) == nil)
    for _ in 0..<6 { fresh.record(["page:discord.com"], to: b, now: now) }
    let suggestion = fresh.suggest(mixed, in: tree, now: now)
    #expect(suggestion?.category == b)
    #expect(suggestion?.reason == "page:discord.com")
}

/// 用户的真实场景：同一 Discord 频道下的世界书、预设、脚本都是 .json，只能靠内容分开
@Test func discordJsonResolvedByContent() {
    var tree = CategoryTree()
    var learner = CategoryLearner()
    let samples = [("世界书", ["json:entries"]), ("预设", ["json:prompts", "json:temperature", "json:top_p"]),
                   ("脚本", ["json:scriptname", "json:findregex"])]
    let url = URL(string: "https://cdn.discordapp.com/attachments/42/7/file.json")
    let page = URL(string: "https://discord.com/channels/1/42")
    var ids: [UUID] = []
    for (name, content) in samples {
        let id = tree.add(name, parent: nil)!.id
        ids.append(id)
        let keys = LearnFeatures.make(url: url, referrer: page, fileName: "file.json", content: content)
        for _ in 0..<3 { learner.record(keys, to: id) }
    }
    // 下载前只有链接：三类混在一起，不乱猜
    #expect(learner.suggest(LearnFeatures.make(url: url, referrer: page, fileName: "new.json"), in: tree) == nil)
    // 下完带上内容：各归各位
    for (index, (_, content)) in samples.enumerated() {
        let keys = LearnFeatures.make(url: url, referrer: page, fileName: "new.json", content: content)
        #expect(learner.suggest(keys, in: tree)?.category == ids[index])
    }
}

@Test func evictionUsesDecayedVotes() {
    var tree = CategoryTree()
    let ids = (0..<9).map { tree.add("分类\($0)", parent: nil)!.id }
    let old = Date.now
    let now = old.addingTimeInterval(180 * 86_400)
    let current = (0..<512).map { "word:w\($0)" }
    var learner = CategoryLearner()
    for _ in 0..<4 { learner.record(["word:old"], to: ids[0], now: old) }
    learner.record(current, to: ids[0], now: now)
    #expect(learner.suggest(["word:old"], in: tree, now: old) == nil)
    learner = CategoryLearner()
    for _ in 0..<4 { learner.record(["ext:json"], to: ids[0], now: old) }
    for id in ids.dropFirst() { learner.record(["ext:json"], to: id, now: now) }
    learner.forget(Set(ids.dropFirst()))
    #expect(learner.suggest(["ext:json"], in: tree, now: old) == nil)
}
