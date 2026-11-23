// 界面状态与任务列表：调度下载引擎、网络出错自动重试、任务和设置存盘
import AppKit
import DownloaderCore
import Foundation
import Network
import Observation
import UserNotifications

struct AppSettings: Equatable, Codable {
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

/// 存盘内容：任务列表和设置
private struct SavedState: Codable {
    var items: [DownloadItem]
    var settings: AppSettings
}

@MainActor
@Observable
final class DownloadStore {
    private static let toastDuration = Duration.milliseconds(1800)
    /// 等待重试时多久看一眼网络是否恢复
    private static let retryPollInterval = Duration.milliseconds(500)
    private static let speedSmoothing = 0.3
    private static let minSpeedSampleSeconds = 0.2
    private static let retryMessage = "网络中断，正在重试"

    var items: [DownloadItem] = []
    var settings = AppSettings() {
        didSet {
            if settings.notify, !oldValue.notify { requestNotificationPermission() }
            reschedule()
        }
    }
    /// nil 表示「全部」
    var category: FileCategory?
    var statusFilter: StatusFilter = .all
    var dialog: Dialog?
    var toastText: String?

    @ObservationIgnored private var toastToken = 0
    @ObservationIgnored private var jobs: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var speedSamples: [UUID: (time: ContinuousClock.Instant, received: Int64)] = [:]
    /// 网络每恢复一次加一，等待重试的任务看到变化就立刻续传
    @ObservationIgnored private var networkGeneration = 0
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private let stateFile: URL?

    init(stateFile: URL? = DownloadStore.defaultStateFile()) {
        self.stateFile = stateFile
        guard let stateFile, let data = try? Data(contentsOf: stateFile) else { return }
        do {
            let saved = try JSONDecoder().decode(SavedState.self, from: data)
            settings = saved.settings
            // 上次没下完的重新排队，start() 时自动续传
            items = saved.items.map { item in
                var item = item
                if item.status == .downloading { item.status = .queued }
                item.speed = 0
                if item.status != .failed { item.message = nil }
                return item
            }
        } catch {
            showToast("读取任务列表失败：\(error.localizedDescription)")
        }
    }

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

    var downloadDirDisplay: String {
        (settings.downloadDir.path as NSString).abbreviatingWithTildeInPath
    }

    // MARK: 操作

    func present(_ dialog: Dialog) { self.dialog = dialog }
    func dismissDialog() { dialog = nil }

    /// 开始工作：监听网络、续传上次没下完的任务
    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.networkGeneration += 1 }
        }
        monitor.start(queue: .global(qos: .utility))
        self.monitor = monitor
        if settings.notify { requestNotificationPermission() }
        reschedule()
    }

    func add(urls: [URL]) {
        for url in urls {
            let fileName = Naming.fileName(from: url)
            let dir = directory(for: .of(fileName: fileName))
            let name = Naming.uniqueName(fileName, taken: takenNames(in: dir))
            items.append(DownloadItem(name: name, url: url, destination: dir.appending(path: name), size: 0))
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
            items[i].message = nil
        case .paused, .failed:
            items[i].status = .queued
            items[i].message = nil
        case .completed:
            if let destination = items[i].destination {
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            }
        }
        reschedule()
    }

    /// 移除任务；没下完的顺手删掉临时文件，已完成的文件保留
    func remove(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        let job = jobs.removeValue(forKey: id)
        job?.cancel()
        reschedule()
        guard item.status != .completed, let destination = item.destination else { return }
        Task {
            // 等引擎停下、写完最后一次续传记录再删，免得删了又被写回来
            await job?.value
            let part = destination.appendingPathExtension("part")
            for file in [part, part.appendingPathExtension("json")] {
                try? FileManager.default.removeItem(at: file)  // 文件可能本来就不存在
            }
        }
    }

    func pauseOrResumeAll() {
        let running = isRunning
        for i in items.indices {
            let status = items[i].status
            if running, status == .downloading || status == .queued {
                items[i].status = .paused
                items[i].speed = 0
                items[i].message = nil
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

    // MARK: 调度

    /// 按上限排好下载/排队，再让正在跑的引擎任务和状态对上，最后存盘
    private func reschedule() {
        Scheduler.schedule(&items, maxActive: settings.maxActive)
        for item in items {
            let running = jobs[item.id] != nil
            if item.status == .downloading, !running {
                jobs[item.id] = Task { [weak self] in await self?.run(item.id) }
            } else if item.status != .downloading, running {
                jobs.removeValue(forKey: item.id)?.cancel()
            }
        }
        save()
    }

    private func directory(for category: FileCategory) -> URL {
        settings.classify ? settings.downloadDir.appending(path: category.displayName) : settings.downloadDir
    }

    /// 目录里已有的文件 + 列表里要下到这个目录的任务，新任务不能和它们重名
    private func takenNames(in dir: URL) -> Set<String> {
        let onDisk = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []  // 目录还没建时为空
        let planned = items.compactMap(\.destination)
            .filter { $0.deletingLastPathComponent().path == dir.path }
            .map(\.lastPathComponent)
        return Set(onDisk + planned)
    }

    /// 跑一个任务直到完成、失败或被取消；网络类错误按退避自动重试，引擎每次都从断点续上
    private func run(_ id: UUID) async {
        var attempt = 0
        while let item = items.first(where: { $0.id == id }), let url = item.url, let destination = item.destination {
            do {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                let job = DownloadJob(url: url, destination: destination, segments: settings.threads)
                _ = try await DownloadEngine.run(job) { [weak self] progress in
                    Task { @MainActor in self?.apply(progress, to: id) }
                }
                finish(id)
                return
            } catch {
                if Task.isCancelled || error is CancellationError { return }
                attempt += 1
                guard Retry.isTransient(error), attempt < Retry.maxAttempts else {
                    fail(id, error.localizedDescription)
                    return
                }
                update(id) {
                    $0.message = Self.retryMessage
                    $0.speed = 0
                }
                guard await waitForRetry(Retry.delay(attempt: attempt)) else { return }
            }
        }
    }

    /// 等到退避时间到或网络恢复；被取消返回 false
    private func waitForRetry(_ delay: Duration) async -> Bool {
        let deadline = ContinuousClock.now + delay
        let generation = networkGeneration
        while ContinuousClock.now < deadline, networkGeneration == generation {
            do { try await Task.sleep(for: Self.retryPollInterval) } catch { return false }
        }
        return !Task.isCancelled
    }

    private func apply(_ progress: DownloadProgress, to id: UUID) {
        let now = ContinuousClock.now
        update(id) { item in
            guard item.status == .downloading else { return }
            item.received = progress.received
            item.size = progress.total ?? 0
            item.message = nil
            if let sample = speedSamples[id] {
                let seconds = (now - sample.time) / .seconds(1)
                guard seconds >= Self.minSpeedSampleSeconds else { return }
                let instant = Double(max(0, progress.received - sample.received)) / seconds
                item.speed = item.speed == 0 ? instant : item.speed + (instant - item.speed) * Self.speedSmoothing
            }
            speedSamples[id] = (now, progress.received)
        }
    }

    private func finish(_ id: UUID) {
        jobs[id] = nil
        speedSamples[id] = nil
        update(id) {
            $0.status = .completed
            $0.received = max($0.received, $0.size)
            $0.size = $0.received
            $0.speed = 0
            $0.message = nil
        }
        if settings.notify, let name = items.first(where: { $0.id == id })?.name {
            showToast("下载完成：\(name)")
            postNotification("下载完成", body: name)
        }
        reschedule()
    }

    private func fail(_ id: UUID, _ message: String) {
        jobs[id] = nil
        speedSamples[id] = nil
        update(id) {
            $0.status = .failed
            $0.speed = 0
            $0.message = message
        }
        reschedule()
    }

    private func update(_ id: UUID, _ change: (inout DownloadItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
    }

    // MARK: 存盘

    private static func defaultStateFile() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return support.appending(path: "Downloader/state.json")
    }

    /// 只在任务增删、状态变化、改设置时存；进度以引擎的 .part.json 为准，不用每次都存
    private func save() {
        guard let stateFile else { return }
        do {
            try FileManager.default.createDirectory(at: stateFile.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(SavedState(items: items, settings: settings))
            try data.write(to: stateFile, options: .atomic)
        } catch {
            showToast("保存任务列表失败：\(error.localizedDescription)")
        }
    }

    // MARK: 通知

    /// swift run 直接跑可执行文件时没有 app 包，系统通知用不了，只留应用内提示
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    private func requestNotificationPermission() {
        guard canNotify else { return }
        // 用户拒绝也没关系，下载完成时还有应用内提示
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postNotification(_ title: String, body: String) {
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
