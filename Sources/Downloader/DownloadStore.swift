// 界面状态与任务列表：调度下载引擎、网络出错自动重试、自定义分类、外观，任务和设置存盘
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
    var learn = true
    var notify = true
    var menuBar = true
    var theme = ThemeChoice.system
    /// 正文字号 px
    var textSize = TextSize.base
    /// nil 表示跟随系统
    var language: Language?
    var background: URL?

    init() {}

    /// 老版本存的设置缺新字段，缺的用默认值
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        downloadDir = try c.decodeIfPresent(URL.self, forKey: .downloadDir) ?? d.downloadDir
        maxActive = try c.decodeIfPresent(Int.self, forKey: .maxActive) ?? d.maxActive
        threads = try c.decodeIfPresent(Int.self, forKey: .threads) ?? d.threads
        classify = try c.decodeIfPresent(Bool.self, forKey: .classify) ?? d.classify
        learn = try c.decodeIfPresent(Bool.self, forKey: .learn) ?? d.learn
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? d.notify
        menuBar = try c.decodeIfPresent(Bool.self, forKey: .menuBar) ?? d.menuBar
        theme = try c.decodeIfPresent(ThemeChoice.self, forKey: .theme) ?? d.theme
        // 老版本的 fontSize（小/标准/大）不迁移，回到默认 13px
        let size = try c.decodeIfPresent(Int.self, forKey: .textSize)
        textSize = size.flatMap { TextSize.options.contains($0) ? $0 : nil } ?? d.textSize
        language = try c.decodeIfPresent(Language.self, forKey: .language)
        background = try c.decodeIfPresent(URL.self, forKey: .background)
    }
}

enum StatusFilter: CaseIterable, Identifiable {
    case all, active, done
    var id: Self { self }
    func title(_ language: Language) -> String {
        switch self {
        case .all: language.pick("全部", "All")
        case .active: language.pick("进行中", "Active")
        case .done: language.pick("已完成", "Done")
        }
    }
}

/// 侧栏选中项：全部、某个类型、某个自定义分类
enum SidebarSelection: Hashable {
    case all
    case type(FileCategory)
    case group(UUID)
}

/// 新任务：浏览器接管来的会带文件名和请求头
private struct NewTask {
    var url: URL
    var fileName: String?
    var referrer: URL?
    var headers: [String: String] = [:]
}

enum Dialog: Equatable {
    case add, settings
}

/// 存盘内容：任务列表、设置、自定义分类和学到的习惯（后两项老版本没有）
private struct SavedState: Codable {
    var items: [DownloadItem]
    var settings: AppSettings
    var categories: CategoryTree?
    var learner: CategoryLearner?
}

@MainActor
@Observable
final class DownloadStore {
    private static let toastDuration = Duration.milliseconds(1800)
    /// 等待重试时多久看一眼网络是否恢复
    private static let retryPollInterval = Duration.milliseconds(500)
    private static let speedSmoothing = 0.3
    private static let minSpeedSampleSeconds = 0.2

    var items: [DownloadItem] = []
    var settings = AppSettings() {
        didSet {
            if settings.notify, !oldValue.notify { requestNotificationPermission() }
            if settings.background != oldValue.background { loadBackground() }
            if settings.theme != oldValue.theme || settings.background != oldValue.background { applyAppearance() }
            reschedule()
        }
    }
    var categories = CategoryTree()
    var selection = SidebarSelection.all
    var statusFilter: StatusFilter = .all
    var dialog: Dialog?
    var toastText: String?
    /// 正在侧栏里改名的分类
    var renaming: UUID?
    private(set) var backgroundImage: NSImage?
    private var backgroundIsBright = true
    /// 浏览器扩展最近一次连上的记录，nil 表示还没连上过
    var browserLink: ExtensionLink?

    @ObservationIgnored private var learner = CategoryLearner()
    /// 浏览器带来的 Cookie 等请求头只放内存，不写进存盘文件
    @ObservationIgnored private var headers: [UUID: [String: String]] = [:]

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
            categories = saved.categories ?? CategoryTree()
            learner = saved.learner ?? CategoryLearner()
            // 上次没下完的重新排队，start() 时自动续传
            items = saved.items.map { item in
                var item = item
                if item.status == .downloading { item.status = .queued }
                item.speed = 0
                if item.status != .failed { item.message = nil }
                return item
            }
        } catch {
            showToast(language.pick("读取任务列表失败：", "Couldn't read saved tasks: ") + error.localizedDescription)
        }
        loadBackground()
    }

    // MARK: 派生数据

    var language: Language { settings.language ?? .system }
    /// 启动时的语言，给窗口标题这类不随设置刷新的地方用
    @ObservationIgnored private(set) lazy var launchLanguage = language

    var theme: Theme {
        Theme.make(settings.theme, textSize: settings.textSize,
                   backgroundIsBright: backgroundImage == nil ? nil : backgroundIsBright)
    }

    var visibleItems: [DownloadItem] {
        items.filter { item in
            matches(item, selection) &&
                (statusFilter == .all || (statusFilter == .done) == (item.status == .completed))
        }
    }

    /// 筛选条件变了列表才重建、播入场动画
    var filterKey: String { "\(selection)-\(statusFilter)" }

    var title: String {
        switch selection {
        case .all: language.pick("全部", "All")
        case .type(let type): type.name(language)
        case .group(let id): categories[id]?.name ?? ""
        }
    }

    var activeItems: [DownloadItem] { items.filter { $0.status == .downloading } }
    var totalSpeed: Double { activeItems.reduce(0) { $0 + $1.speed } }
    var isRunning: Bool { items.contains { $0.status == .downloading || $0.status == .queued } }
    var hasPaused: Bool { items.contains { $0.status == .paused } }

    func count(for selection: SidebarSelection) -> Int {
        items.filter { matches($0, selection) }.count
    }

    /// 选中上级分类时连子孙分类的任务一起显示
    private func matches(_ item: DownloadItem, _ selection: SidebarSelection) -> Bool {
        switch selection {
        case .all: true
        case .type(let type): item.category == type
        case .group(let id): item.group.map { categories.subtree(of: id).contains($0) } ?? false
        }
    }

    func groupName(of item: DownloadItem) -> String? {
        item.group.flatMap { categories[$0]?.name }
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
        applyAppearance()
        reschedule()
    }

    func add(urls: [URL]) {
        add(urls.map { NewTask(url: $0) })
    }

    /// 浏览器扩展经 downloader://add 交来的下载；链接不合法直接拒绝
    func handle(_ url: URL) {
        guard let request = BrowserRequest.parse(url) else {
            showToast(language.pick("无法识别的下载请求", "Unrecognized download request"))
            return
        }
        add([NewTask(url: request.url, fileName: request.filename, referrer: request.referrer.flatMap(URL.init(string:)),
                     headers: request.headers)])
    }

    /// 学过习惯的新任务先按链接放进对应分类，下完再按内容复判
    private func add(_ tasks: [NewTask]) {
        var learned: CategoryLearner.Suggestion?
        for task in tasks {
            let fileName = task.fileName ?? Naming.fileName(from: task.url)
            var item = DownloadItem(name: fileName, url: task.url, size: 0)
            item.features = LearnFeatures.make(url: task.url, referrer: task.referrer, fileName: fileName)
            if settings.learn, let suggestion = learner.suggest(item.features ?? [], in: categories) {
                item.group = suggestion.category
                item.autoSorted = true
                learned = suggestion
            }
            let dir = directory(for: item)
            item.name = Naming.uniqueName(fileName, taken: takenNames(in: dir))
            item.destination = dir.appending(path: item.name)
            if !task.headers.isEmpty { headers[item.id] = task.headers }
            items.append(item)
        }
        reschedule()
        if let learned, tasks.count == 1 {
            showToast(sortedMessage(learned))
        } else {
            showToast(language.pick("已添加 \(tasks.count) 个任务", "Added \(tasks.count) \(tasks.count == 1 ? "task" : "tasks")"))
        }
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
        headers[id] = nil
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

    // MARK: 自定义分类

    func level(of selection: SidebarSelection) -> Int {
        switch selection {
        case .all: 1
        case .type: 2
        case .group(let id): categories.depth(of: id)
        }
    }

    func newCategory(parent: UUID?) {
        guard let category = categories.add(language.pick("新分类", "New Category"), parent: parent) else { return }
        renaming = category.id
        save()
    }

    func rename(_ id: UUID, to name: String) {
        categories.rename(id, to: name)
        renaming = nil
        save()
    }

    /// 删分类连同子分类，里面的任务保留、只是不再归类，文件留在原地
    func deleteCategory(_ id: UUID) {
        guard let name = categories[id]?.name else { return }
        let removed = categories.remove(id)
        learner.forget(removed)
        for i in items.indices where items[i].group.map(removed.contains) == true { items[i].group = nil }
        if case .group(let selected) = selection, removed.contains(selected) { selection = .all }
        save()
        showToast(language.pick("已删除「\(name)」，里面的任务保留", "Deleted “\(name)”; its tasks were kept"))
    }

    /// 手动归类：给新分类加票，自动归错的给原分类扣票；已下完的文件立刻挪进分类文件夹，没下完的等下完再挪
    func assign(_ id: UUID, to group: UUID?) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].group != group else { return }
        if settings.learn {
            let features = items[i].features
                ?? LearnFeatures.make(url: items[i].url, referrer: nil, fileName: items[i].name)
            if items[i].autoSorted == true, let wrong = items[i].group { learner.retract(features, from: wrong) }
            if let group { learner.record(features, to: group) }
        }
        items[i].group = group
        items[i].autoSorted = nil
        if let group, let name = categories[group]?.name {
            relocate(id)
            showToast(language.pick("已移到「\(name)」", "Moved to “\(name)”"))
        }
        save()
    }

    /// 下完按文件内容再判断一次；用户手动归过类的不动。返回改了的分类
    private func resort(_ id: UUID) -> CategoryLearner.Suggestion? {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].group == nil || items[i].autoSorted == true, let file = items[i].destination else { return nil }
        let content: [String]
        do {
            content = try ContentFingerprint.features(of: file)
        } catch {
            // 内容读不出来（比如 JSON 写坏了）只是少了内容特征，照链接特征的结果走，不打扰用户
            content = []
        }
        guard !content.isEmpty else { return nil }
        let features = (items[i].features ?? LearnFeatures.make(url: items[i].url, referrer: nil, fileName: items[i].name))
            + content
        items[i].features = features
        guard let suggestion = learner.suggest(features, in: categories),
              suggestion.category != items[i].group else { return nil }
        items[i].group = suggestion.category
        items[i].autoSorted = true
        return suggestion
    }

    /// 「已按习惯放进『世界书』· 文件内容相似」：说明是按哪条习惯分的
    private func sortedMessage(_ suggestion: CategoryLearner.Suggestion) -> String {
        let name = categories[suggestion.category]?.name ?? ""
        let kind = suggestion.reason.prefix { $0 != ":" }
        let value = suggestion.reason.drop { $0 != ":" }.dropFirst()
        let reason = switch kind {
        case "json", "png": language.pick("文件内容相似", "similar content")
        case "ext": language.pick(".\(value) 文件", ".\(value) files")
        case "word": language.pick("文件名含「\(value)」", "name contains “\(value)”")
        default: language.pick("来自 \(value.prefix { $0 != "/" })", "from \(value.prefix { $0 != "/" })")
        }
        return language.pick("已按习惯放进「\(name)」· \(reason)", "Sorted into “\(name)” by habit · \(reason)")
    }

    /// 已完成且归了分类的文件挪到分类对应的文件夹，重名自动加序号
    private func relocate(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].status == .completed,
              items[i].group != nil, let source = items[i].destination else { return }
        let dir = directory(for: items[i])
        guard source.deletingLastPathComponent().standardizedFileURL != dir.standardizedFileURL else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let name = Naming.uniqueName(source.lastPathComponent, taken: takenNames(in: dir))
            let target = dir.appending(path: name)
            try FileManager.default.moveItem(at: source, to: target)
            items[i].destination = target
            items[i].name = name
        } catch {
            showToast(language.pick("移动文件失败：", "Couldn't move the file: ") + error.localizedDescription)
        }
    }

    // MARK: 外观

    /// 主题有固定深浅色时整个 App（含菜单、面板）跟着切，跟随系统时交还给系统
    /// 放到下一轮 runloop：在 SwiftUI 更新里同步改外观会触发重入刷新，递归到栈溢出
    private func applyAppearance() {
        let name: NSAppearance.Name? = theme.scheme.map { $0 == .dark ? .darkAqua : .aqua }
        Task { @MainActor in
            guard let app = NSApp, app.appearance?.name != name else { return }
            app.appearance = name.flatMap(NSAppearance.init(named:))
        }
    }

    /// 读背景图并判断明暗；读不出来就当没设，提示一下
    private func loadBackground() {
        guard let url = settings.background else {
            backgroundImage = nil
            return
        }
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            backgroundImage = nil
            showToast(language.pick("背景图片读不出来", "Couldn't read the background image"))
            return
        }
        backgroundIsBright = ImageTone.isBright(cgImage)
        backgroundImage = image
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

    /// 有自定义分类放进分类路径，否则按设置决定要不要按类型分文件夹（文件夹名用当时的界面语言）
    private func directory(for item: DownloadItem) -> URL {
        if let group = item.group, categories[group] != nil {
            return categories.path(of: group).reduce(settings.downloadDir) { $0.appending(path: $1.name) }
        }
        return settings.classify ? settings.downloadDir.appending(path: item.category.name(language)) : settings.downloadDir
    }

    /// 目录里已有的文件 + 列表里要下到这个目录的任务，新任务不能和它们重名
    func takenNames(in dir: URL) -> Set<String> {
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
                let job = DownloadJob(url: url, destination: destination, segments: settings.threads,
                                      headers: headers[id] ?? [:])
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
                let message = language.pick("网络中断，正在重试", "Network lost, retrying")
                update(id) {
                    $0.message = message
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
        headers[id] = nil
        update(id) {
            $0.status = .completed
            $0.received = max($0.received, $0.size)
            $0.size = $0.received
            $0.speed = 0
            $0.message = nil
        }
        let resorted = settings.learn ? resort(id) : nil
        relocate(id)
        if let resorted {
            showToast(sortedMessage(resorted))
        } else if settings.notify, let name = items.first(where: { $0.id == id })?.name {
            showToast(language.pick("下载完成：", "Downloaded: ") + name)
            postNotification(language.pick("下载完成", "Download complete"), body: name)
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
            let data = try JSONEncoder().encode(SavedState(items: items, settings: settings,
                                                            categories: categories, learner: learner))
            try data.write(to: stateFile, options: .atomic)
        } catch {
            showToast(language.pick("保存任务列表失败：", "Couldn't save tasks: ") + error.localizedDescription)
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
