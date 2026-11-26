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
    #expect(Naming.uniqueName("Report.ZIP", taken: ["report.zip", "REPORT (1).zip"]) == "Report (2).ZIP")
}

@Test func partialFilesReserveBaseName() {
    #expect(Naming.partialBaseName("Report.ZIP.part") == "Report.ZIP")
    #expect(Naming.partialBaseName("Report.ZIP.PART.JSON") == "Report.ZIP")
    #expect(Naming.partialBaseName("notes.part.part.json") == "notes.part")
    #expect(Naming.partialBaseName("notes.part.json.bak") == nil)
    #expect(Naming.partialBaseName(".part") == nil)
}

@Test func parseKeepsOnlyWebLinks() {
    let urls = Naming.parseURLs("https://x.com/a.zip\nabc ftp://y.com/b http://z.cn/%E6%B5%8B.mkv")
    #expect(urls.map(\.absoluteString) == ["https://x.com/a.zip", "http://z.cn/%E6%B5%8B.mkv"])
    #expect(Naming.fileName(from: urls[1]) == "测.mkv")
    #expect(Naming.fileName(from: URL(string: "https://x.com/")!) == "download")
}

/// GitHub 发布下载会重定向到签名地址，路径末尾是一串 ID，真名在参数里
@Test func fileNameFromSignedURL() {
    // 2026-11 真实 GitHub 签名地址的参数（签名部分省略）：rscd 在前且用 + 当空格
    let github = URL(string: "https://release-assets.githubusercontent.com/github-production-release-asset/1/ff3f1a06-e9f4-41a0-a124-0ddcf2dd1d58?sp=r&sv=2018-11-09&rscd=attachment%3B+filename%3DNAI_Launcher_macOS_4.4.0%2B47_Portable.zip&rsct=application%2Foctet-stream&response-content-disposition=attachment%3B%20filename%3DNAI_Launcher_macOS_4.4.0%2B47_Portable.zip&response-content-type=application%2Foctet-stream")!
    #expect(Naming.fileName(from: github) == "NAI_Launcher_macOS_4.4.0+47_Portable.zip")
    let azure = URL(string: "https://a.blob.core.windows.net/c/123?rscd=attachment%3B%20filename%2A%3DUTF-8%27%27%25E6%25B5%258B.zip")!
    #expect(Naming.fileName(from: azure) == "测.zip")
    // 2026-11 真实 Civitai（Backblaze B2）签名地址，Authorization 省略：路径是简写名，真名带引号放在 b2ContentDisposition
    let b2 = URL(string: "https://b2-large.civitai.com/file/civitai-modelfiles/model/1172194/krea2AnimeV14Q4KM.d46a3c79f2fe2ab26a0b7ae0bea74563.gguf?b2ContentDisposition=attachment%3B+filename%3D%22krea_2_anime_v1.4-Q4_K_M.gguf%22")!
    #expect(Naming.fileName(from: b2) == "krea_2_anime_v1.4-Q4_K_M.gguf")
    #expect(Naming.fileName(fromDisposition: #"attachment; filename="../../etc/a.txt""#) == "a.txt")
    #expect(Naming.fileName(fromDisposition: "inline") == nil)
    #expect(Naming.fileName(from: URL(string: "https://x.com/a.zip?response-content-disposition=inline")!) == "a.zip")
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
