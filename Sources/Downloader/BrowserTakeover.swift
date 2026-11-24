// 浏览器接管：启动时注册宿主；设置里一键把扩展放进下载文件夹，打开访达和浏览器扩展页，拖进去由用户自己来
import AppKit
import DownloaderCore

extension DownloadStore {
    private static var support: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    /// 每次启动都注册一遍，App 挪了位置也能自动修好；swift run 启动时没有宿主，跳过
    func installBrowserHost() {
        guard let support = Self.support,
              let host = Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "DownloaderHost"),
              FileManager.default.isExecutableFile(atPath: host.path) else { return }
        do {
            _ = try BrowserHost.install(hostPath: host, support: support)
        } catch {
            showToast(language.pick("注册浏览器宿主失败：", "Couldn't register the browser host: ") + error.localizedDescription)
        }
    }

    /// 读扩展最近一次连上的记录；记录文件坏了当作未连接，用户点「接管」重装一次就会重写
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

    /// 复制扩展到下载文件夹并在访达里选中，再用浏览器打开扩展页
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
            showToast(language.pick("放扩展失败：", "Couldn't copy the extension: ") + error.localizedDescription)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
        Task {
            do {
                _ = try await NSWorkspace.shared.open([browser.page], withApplicationAt: browser.app,
                                                      configuration: NSWorkspace.OpenConfiguration())
            } catch {
                showToast(language.pick("打不开浏览器：", "Couldn't open the browser: ") + error.localizedDescription)
                return
            }
            // 浏览器第一次启动才建数据目录，打开后再注册一次宿主
            installBrowserHost()
            showToast(language.pick("打开扩展页右上角的「开发者模式」，把访达里的「下载器扩展」文件夹拖进去",
                                    "Turn on Developer mode on the extensions page, then drag the “Downloader Extension” folder from Finder onto it"))
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

    /// 放到下载文件夹的「下载器扩展」；同名文件夹是旧版扩展就覆盖，是别的东西就换个名字
    private func placeExtension(from source: URL) throws -> URL {
        let files = FileManager.default
        let root = settings.downloadDir
        var target = root.appending(path: language.pick("下载器扩展", "Downloader Extension"))
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        if files.fileExists(atPath: target.path), !isOurExtension(target) {
            target = root.appending(path: Naming.uniqueName(target.lastPathComponent, taken: takenNames(in: root)))
        }
        let staged = files.temporaryDirectory.appending(path: UUID().uuidString)
        try files.copyItem(at: source, to: staged)
        if files.fileExists(atPath: target.path) {
            _ = try files.replaceItemAt(target, withItemAt: staged)
        } else {
            try files.moveItem(at: staged, to: target)
        }
        return target
    }

    /// 看 manifest 里的固定扩展 ID 公钥，认出是不是之前放的扩展
    private func isOurExtension(_ folder: URL) -> Bool {
        guard let source = Bundle.main.url(forResource: "ChromeExtension", withExtension: nil),
              let ours = manifestKey(source.appending(path: "manifest.json")),
              let theirs = manifestKey(folder.appending(path: "manifest.json")) else { return false }
        return ours == theirs
    }

    private func manifestKey(_ file: URL) -> String? {
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["key"] as? String
    }
}
