// 界面状态与任务列表；目前用模拟数据跑进度，接入真实下载引擎时只替换 tick 和增删任务的实现
import AppKit
import DownloaderCore
import Foundation
import Observation

struct AppSettings: Equatable {
    var downloadDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    var maxActive = 3
    /// 每个任务分几段，0 表示自动
    var threads = 0
    var classify = true
    var notify = true
}

enum StatusFilter: CaseIterable, Identifiable {
    case all, active, done
    var id: Self { self }
    var title: String {
        switch self {
        case .all: "全部"
        case .active: "进行中"
        case .done: "已完成"
        }
    }
}

enum Dialog: Equatable {
    case add, settings
}

@MainActor
@Observable
final class DownloadStore {
    private static let tickInterval = Duration.milliseconds(500)
    private static let toastDuration = Duration.milliseconds(1800)
    private static let megabyte = 1024.0 * 1024

    var items: [DownloadItem] = []
    var settings = AppSettings() {
        didSet { Scheduler.schedule(&items, maxActive: settings.maxActive) }
    }
    /// nil 表示「全部」
    var category: FileCategory?
    var statusFilter: StatusFilter = .all
    var dialog: Dialog?
    var toastText: String?

    @ObservationIgnored private var baseSpeeds: [UUID: Double] = [:]
    @ObservationIgnored private var toastToken = 0
    @ObservationIgnored private var simulation: Task<Void, Never>?

    // MARK: 派生数据

    var visibleItems: [DownloadItem] {
        items.filter { item in
            (category == nil || item.category == category) &&
                (statusFilter == .all || (statusFilter == .done) == (item.status == .completed))
        }
    }

    /// 筛选条件变了列表才重建、播入场动画
    var filterKey: String { "\(category?.rawValue ?? "all")-\(statusFilter)" }

    var activeItems: [DownloadItem] { items.filter { $0.status == .downloading } }
    var isRunning: Bool { items.contains { $0.status == .downloading || $0.status == .queued } }
    var hasPaused: Bool { items.contains { $0.status == .paused } }

    func count(for category: FileCategory?) -> Int {
        guard let category else { return items.count }
        return items.filter { $0.category == category }.count
    }

    func savePath(for item: DownloadItem) -> String {
        var dir = settings.downloadDir
        if settings.classify { dir.append(path: item.category.displayName) }
        return (dir.appending(path: item.name).path as NSString).abbreviatingWithTildeInPath
    }

    var downloadDirDisplay: String {
        (settings.downloadDir.path as NSString).abbreviatingWithTildeInPath
    }

    // MARK: 操作

    func present(_ dialog: Dialog) { self.dialog = dialog }
    func dismissDialog() { dialog = nil }

    func add(urls: [URL]) {
        var taken = Set(items.map(\.name))
        for url in urls {
            let name = Naming.uniqueName(Naming.fileName(from: url), taken: taken)
            taken.insert(name)
            let size = Int64(Double.random(in: 20...1500) * Self.megabyte)
            appendDemo(DownloadItem(name: name, url: url, size: size))
        }
        reschedule()
        showToast("已添加 \(urls.count) 个任务")
    }

    /// 行内主按钮：下载/排队→暂停，暂停/失败→重新排队，已完成→在访达中显示
    func toggle(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        switch items[i].status {
        case .downloading, .queued:
            items[i].status = .paused
            items[i].speed = 0
        case .paused, .failed:
            items[i].status = .queued
        case .completed:
            // shortcut: 模拟数据没有真实文件，先提示路径，接引擎后改成 NSWorkspace.activateFileViewerSelecting
            showToast(savePath(for: items[i]))
        }
        reschedule()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        reschedule()
    }

    func pauseOrResumeAll() {
        let running = isRunning
        for i in items.indices {
            let status = items[i].status
            if running, status == .downloading || status == .queued {
                items[i].status = .paused
                items[i].speed = 0
            } else if !running, status == .paused {
                items[i].status = .queued
            }
        }
        reschedule()
    }

    func showToast(_ text: String) {
        toastText = text
        toastToken += 1
        let token = toastToken
        Task {
            try? await Task.sleep(for: Self.toastDuration)
            if token == toastToken { toastText = nil }
        }
    }

    private func reschedule() {
        Scheduler.schedule(&items, maxActive: settings.maxActive)
    }

    // MARK: 模拟下载

    private func appendDemo(_ item: DownloadItem) {
        baseSpeeds[item.id] = Double.random(in: 2...12) * Self.megabyte
        items.append(item)
    }

    func startSimulation() {
        guard simulation == nil else { return }
        simulation = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                self?.tick()
            }
        }
    }

    private func tick() {
        let seconds = 0.5
        var finished: [String] = []
        for i in items.indices where items[i].status == .downloading {
            let speed = (baseSpeeds[items[i].id] ?? 4 * Self.megabyte) * Double.random(in: 0.7...1.3)
            items[i].speed = speed
            items[i].received = min(items[i].size, items[i].received + Int64(speed * seconds))
            if items[i].received >= items[i].size {
                items[i].status = .completed
                items[i].speed = 0
                finished.append(items[i].name)
            }
        }
        guard let first = finished.first else { return }
        reschedule()
        if settings.notify { showToast("下载完成：\(first)") }
    }

    static func demo() -> DownloadStore {
        let store = DownloadStore()
        let mb = Self.megabyte
        let gb = mb * 1024
        let samples: [(String, Double, Double, TaskStatus)] = [
            ("WWDC26-Keynote.mp4", 1.9 * gb, 1.18 * gb, .downloading),
            ("macOS-Wallpapers.zip", 820 * mb, 210 * mb, .downloading),
            ("Podcast-Ep42.mp3", 96 * mb, 40 * mb, .downloading),
            ("node-v24.11.0.pkg", 78 * mb, 0, .queued),
            ("Xcode_27.dmg", 12.4 * gb, 3.1 * gb, .paused),
            ("dataset-2026.tar.gz", 640 * mb, 233 * mb, .failed),
            ("年度报告-Q3.pdf", 18 * mb, 18 * mb, .completed),
            ("IMG_2048.heic", 4.2 * mb, 4.2 * mb, .completed),
        ]
        for (name, size, received, status) in samples {
            store.appendDemo(DownloadItem(name: name, size: Int64(size), received: Int64(received), status: status))
        }
        return store
    }
}
