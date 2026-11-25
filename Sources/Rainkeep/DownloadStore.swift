// 界面状态与任务列表：任务增删、外观、存盘；分类见 DownloadStore+Categories，调度见 DownloadStore+Engine
import AppKit
import RainkeepCore
import Foundation
import Network
import Observation

/// 新任务：浏览器接管来的会带文件名和请求头
private struct NewTask {
    var url: URL
    var fileName: String?
    var referrer: URL?
    var headers: [String: String] = [:]
}

@MainActor
@Observable
final class DownloadStore {
    private static let toastDuration = Duration.milliseconds(1800)

    var items: [DownloadItem] = []
    var settings = AppSettings() {
        didSet {
            if settings.notify, !oldValue.notify { SystemNotice.requestPermission() }
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
    /// 等用户确认删除的任务，底部显示确认条
    var pendingDelete: UUID?
    /// 正在侧栏里改名的分类
    var renaming: UUID?
    private(set) var backgroundImage: NSImage?
    private var backgroundIsBright = true
    /// 浏览器扩展最近一次连上的记录，nil 表示还没连上过
    var browserLink: ExtensionLink?

    @ObservationIgnored var learner = CategoryLearner()
    /// 浏览器带来的 Cookie 等请求头只放内存，不写进存盘文件
    @ObservationIgnored var headers: [UUID: [String: String]] = [:]
    /// 服务器在 Content-Disposition 里给的文件名，下完时用
    @ObservationIgnored var serverNames: [UUID: String] = [:]

    @ObservationIgnored private var toastToken = 0
    @ObservationIgnored var jobs: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var speedSamples: [UUID: (time: ContinuousClock.Instant, received: Int64)] = [:]
    /// 网络每恢复一次加一，等待重试的任务看到变化就立刻续传
    @ObservationIgnored var networkGeneration = 0
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private let stateFile: URL?

    init(stateFile: URL? = DownloadStore.defaultStateFile()) {
        self.stateFile = stateFile
        guard let stateFile, let data = try? Data(contentsOf: stateFile) else { return }
        do {
            let saved = try SavedState.restore(from: data)
            settings = saved.settings
            categories = saved.categories ?? CategoryTree()
            learner = saved.learner ?? CategoryLearner()
            items = saved.items
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
        if settings.notify { SystemNotice.requestPermission() }
        applyAppearance()
        reschedule()
    }

    func add(urls: [URL]) {
        add(urls.map { NewTask(url: $0) })
    }

    /// 浏览器扩展经 rainkeep://add 交来的下载；链接不合法直接拒绝
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
            if task.fileName == nil { item.guessedName = true }
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
        serverNames[id] = nil
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

    /// 删除任务和文件：已下完的移到废纸篓（访达里能放回原处），没下完的连同临时文件删掉
    func confirmDelete() {
        let id = pendingDelete
        pendingDelete = nil
        guard let id, let item = items.first(where: { $0.id == id }) else { return }
        guard item.status == .completed, let file = item.destination,
              FileManager.default.fileExists(atPath: file.path) else { return remove(id) }
        do {
            try FileManager.default.trashItem(at: file, resultingItemURL: nil)
        } catch {
            return showToast(language.pick("移到废纸篓失败：", "Couldn't move to the Trash: ") + error.localizedDescription)
        }
        remove(id)
        showToast(language.pick("已将「\(item.name)」移到废纸篓", "Moved “\(item.name)” to the Trash"))
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

    // MARK: 外观

    /// 主题有固定深浅色时整个 App（含菜单、面板）跟着切，跟随系统时交还给系统
    /// 放到下一轮 runloop：在 SwiftUI 更新里同步改外观会触发重入刷新，递归到栈溢出
    func applyAppearance() {
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

    // MARK: 文件位置

    /// 有自定义分类放进分类路径，否则按设置决定要不要按类型分文件夹（文件夹名用当时的界面语言）
    func directory(for item: DownloadItem) -> URL {
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

    // MARK: 存盘

    private static func defaultStateFile() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return support.appending(path: "Rainkeep/state.json")
    }

    /// 只在任务增删、状态变化、改设置时存；进度以引擎的 .part.json 为准，不用每次都存
    func save() {
        guard let stateFile else { return }
        do {
            try FileManager.default.createDirectory(at: stateFile.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try SavedState(items: items, settings: settings, categories: categories, learner: learner).encoded()
            try data.write(to: stateFile, options: .atomic)
        } catch {
            showToast(language.pick("保存任务列表失败：", "Couldn't save tasks: ") + error.localizedDescription)
        }
    }
}
