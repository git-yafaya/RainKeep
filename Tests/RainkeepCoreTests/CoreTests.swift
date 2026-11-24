// RainkeepCore 的分类、命名、链接解析、调度测试
import Foundation
import Testing
@testable import RainkeepCore

@Test func categoryByExtension() {
    #expect(FileCategory.of(fileName: "a.MP4") == .video)
    #expect(FileCategory.of(fileName: "data.tar.gz") == .archive)
    #expect(FileCategory.of(fileName: "Xcode.dmg") == .installer)
    #expect(FileCategory.of(fileName: "README") == .other)
}

@Test func uniqueNameAddsCounter() {
    #expect(Naming.uniqueName("a.heic", taken: []) == "a.heic")
    #expect(Naming.uniqueName("a.heic", taken: ["a.heic", "a (1).heic"]) == "a (2).heic")
    #expect(Naming.uniqueName("README", taken: ["README"]) == "README (1)")
}

@Test func parseKeepsOnlyWebLinks() {
    let urls = Naming.parseURLs("https://x.com/a.zip\nabc ftp://y.com/b http://z.cn/%E6%B5%8B.mkv")
    #expect(urls.map(\.absoluteString) == ["https://x.com/a.zip", "http://z.cn/%E6%B5%8B.mkv"])
    #expect(Naming.fileName(from: urls[1]) == "测.mkv")
    #expect(Naming.fileName(from: URL(string: "https://x.com/")!) == "download")
}

@Test func scheduleTrimsAndFills() {
    var items = (0..<4).map { DownloadItem(name: "\($0).zip", size: 10, status: .downloading) }
    items.append(DownloadItem(name: "q.zip", size: 10, status: .queued))

    Scheduler.schedule(&items, maxActive: 2)
    #expect(items.map(\.status) == [.downloading, .downloading, .queued, .queued, .queued])

    items[0].status = .paused
    Scheduler.schedule(&items, maxActive: 2)
    #expect(items.map(\.status) == [.paused, .downloading, .downloading, .queued, .queued])
}

@Test func summaryText() {
    var item = DownloadItem(name: "a.mp4", size: 2048 * 1024 * 1024, received: 1024 * 1024 * 1024, status: .paused)
    #expect(Format.summary(item) == "已暂停 · 1.0 GB / 2.0 GB")
    item.status = .completed
    #expect(Format.summary(item) == "2.0 GB · 视频")
    #expect(Format.eta(59.2) == "60 秒")
    #expect(Format.eta(90) == "2 分")
}

@Test func retryOnlyTransientErrors() {
    #expect(Retry.isTransient(URLError(.networkConnectionLost)))
    #expect(Retry.isTransient(URLError(.timedOut)))
    #expect(!Retry.isTransient(URLError(.badURL)))
    #expect(!Retry.isTransient(CancellationError()))
    #expect(Retry.delay(attempt: 1) == .seconds(2))
    #expect(Retry.delay(attempt: 3) == .seconds(8))
    #expect(Retry.delay(attempt: 20) == .seconds(60))
}

@Test func summaryShowsRetryMessage() {
    var item = DownloadItem(name: "a.zip", size: 2048, received: 1024, status: .downloading)
    item.message = "网络中断，正在重试"
    #expect(Format.summary(item) == "网络中断，正在重试 · 1 KB / 2 KB")
    item.status = .failed
    item.message = "服务器返回 404"
    #expect(Format.summary(item) == "服务器返回 404 · 1 KB / 2 KB")
}
