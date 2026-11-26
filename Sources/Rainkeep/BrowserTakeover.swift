// 浏览器接管：启动时注册宿主；设置里一键把扩展放进 Application Support，打开访达和浏览器扩展页，拖进去由用户自己来
import AppKit
import RainkeepCore

extension DownloadStore {
    private static var support: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    /// 每次启动都注册一遍，App 挪了位置也能自动修好；swift run 启动时没有宿主，跳过
    func installBrowserHost() {
        guard let support = Self.support,
              let host = Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "RainkeepHost"),
              FileManager.default.isExecutableFile(atPath: host.path) else { return }
        do {
            _ = try BrowserHost.install(hostPath: host, support: support)
        } catch {
            showToast(language.pick("注册浏览器通讯组件失败：", "Couldn't register the native messaging host: ") + error.localizedDescription)
        }
    }

    /// 读扩展最近一次连上的记录；记录文件坏了当作未连接，用户点「重新连接」重装一次就会重写
    func refreshBrowserLink() {
        guard let support = Self.support else { return }
        let link: ExtensionLink?
        do {
            link = try ExtensionLink.load(from: support)
        } catch {
            link = nil
        }
        if link != browserLink { browserLink = link }
    }

    /// 复制扩展到 Application Support 并在访达里选中，再用浏览器打开扩展页
    func connectBrowser() {
        guard let source = Bundle.main.url(forResource: "ChromeExtension", withExtension: nil) else {
            showToast(language.pick("App 里没有扩展，请用 scripts/make-app.sh 打包", "No extension bundled; build with scripts/make-app.sh"))
            return
        }
        guard let browser = preferredBrowser() else {
            showToast(language.pick("没找到 Chrome、Edge、Arc 或 Brave", "Chrome, Edge, Arc or Brave not found"))
            return
        }
        let folder: URL
        do {
            folder = try placeExtension(from: source)
        } catch {
            showToast(language.pick("导出扩展失败：", "Couldn't copy the extension: ") + error.localizedDescription)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
        Task {
            do {
                _ = try await NSWorkspace.shared.open([browser.page], withApplicationAt: browser.app,
                                                      configuration: NSWorkspace.OpenConfiguration())
            } catch {
                showToast(language.pick("无法打开浏览器：", "Couldn't open the browser: ") + error.localizedDescription)
                return
            }
            // 浏览器第一次启动才建数据目录，打开后再注册一次宿主
            installBrowserHost()
            showToast(language.pick("开启扩展页右上角的「开发者模式」，将访达中的「拾雨扩展」拖入页面",
                                    "Turn on “Developer mode” on the Extensions page, then drag “Rainkeep Extension” from Finder into the page"))
        }
    }

    /// 默认浏览器是 Chrome 系就用它，否则用装了的第一个
    private func preferredBrowser() -> (app: URL, page: URL)? {
        let workspace = NSWorkspace.shared
        let installed = ChromiumBrowser.all.compactMap { browser in
            workspace.urlForApplication(withBundleIdentifier: browser.bundleID).map { (browser, $0) }
        }
        let defaultApp = workspace.urlForApplication(toOpen: URL(string: "https://example.com")!)
        let pick = installed.first { $0.1 == defaultApp } ?? installed.first
        return pick.map { (app: $0.1, page: $0.0.extensionsPage) }
    }

    /// 放到 Application Support/Rainkeep 下的「拾雨扩展.bundle」：浏览器一直从这里加载，不放下载文件夹，免得清理下载时被删；
    /// .bundle 让访达把它显示成一个整体、双击打不开，用户只能整个拖进浏览器。目录归拾雨自己管，同名的直接覆盖
    private func placeExtension(from source: URL) throws -> URL {
        guard let support = Self.support else { throw CocoaError(.fileNoSuchFile) }
        let files = FileManager.default
        let root = support.appending(path: "Rainkeep", directoryHint: .isDirectory)
        let target = root.appending(path: language.pick("拾雨扩展", "Rainkeep Extension") + ".bundle")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let staged = files.temporaryDirectory.appending(path: UUID().uuidString)
        try files.copyItem(at: source, to: staged)
        if files.fileExists(atPath: target.path) {
            _ = try files.replaceItemAt(target, withItemAt: staged)
        } else {
            try files.moveItem(at: staged, to: target)
        }
        return target
    }
}
