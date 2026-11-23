// 自定义分类树、习惯学习、背景图明暗、英文文案测试
import CoreGraphics
import Foundation
import Testing
@testable import DownloaderCore

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

    learner.record(url: url, fileName: "a.pdf", category: work.id)
    learner.record(url: url, fileName: "b.pdf", category: work.id)
    #expect(learner.suggest(url: url, fileName: "c.pdf", in: tree) == nil)
    learner.record(url: url, fileName: "c.pdf", category: work.id)
    #expect(learner.suggest(url: URL(string: "https://example.com/x.zip"), fileName: "x.zip", in: tree) == work.id)
    #expect(learner.suggest(url: URL(string: "https://other.org/y.pdf"), fileName: "y.pdf", in: tree) == work.id)

    // 换了分类重新计数；分类删掉后不再建议
    learner.record(url: url, fileName: "d.pdf", category: other.id)
    #expect(learner.suggest(url: url, fileName: "e.pdf", in: tree) == nil)
    tree.remove(work.id)
    #expect(learner.suggest(url: URL(string: "https://none.io/f.pdf"), fileName: "f.pdf", in: tree) == nil)
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
    #expect(Format.summary(item, .en) == "2.0 GB · Video")
    #expect(Format.summary(item, .en, groupName: "Work") == "2.0 GB · Work")
    #expect(Format.eta(90, .en) == "2 min")
}
