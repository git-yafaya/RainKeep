// 应用入口：主窗口、菜单栏图标面板、菜单快捷键（⌘N 添加、⌘, 设置），以及浏览器扩展发来的 downloader:// 链接
import AppKit
import SwiftUI

@main
struct DownloaderApp: App {
    static let mainWindow = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // App.body 不读任何可观察状态：读了的话改设置会让整个场景树重算，在 SwiftUI 里递归到栈溢出崩溃
    // 需要跟设置变的部分拆进下面各自的 Commands / Scene，场景闭包返回值也擦成 AnyView
    var body: some Scene {
        let store = appDelegate.store
        Window(store.launchLanguage.pick("下载器", "Downloader"), id: Self.mainWindow) {
            AnyView(ContentView()
                .modifier(Themed())
                .environment(store)
                .frame(minWidth: 720, minHeight: 440))
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 640)
        .commands { AppCommands(store: store) }

        MenuBarScene(store: store)
    }
}

/// ⌘N 添加、⌘, 设置
private struct AppCommands: Commands {
    let store: DownloadStore

    var body: some Commands {
        let language = store.language
        CommandGroup(replacing: .newItem) {
            Button(language.pick("添加下载…", "Add Download…")) { store.present(.add) }.keyboardShortcut("n")
        }
        CommandGroup(replacing: .appSettings) {
            Button(language.pick("设置…", "Settings…")) { store.present(.settings) }.keyboardShortcut(",")
        }
    }
}

/// 菜单栏图标和面板，设置里能关
private struct MenuBarScene: Scene {
    @Bindable var store: DownloadStore

    var body: some Scene {
        MenuBarExtra(isInserted: $store.settings.menuBar) {
            AnyView(MenuBarPanel()
                .modifier(Themed())
                .environment(store))
        } label: {
            AnyView(MenuBarLabel().environment(store))
        }
        .menuBarExtraStyle(.window)
    }
}

/// 持有任务仓库，这样窗口关了、只剩菜单栏图标时下载照常跑；也负责接收 downloader:// 链接
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = DownloadStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // swift run 启动时没有 app 包，要手动设成普通前台应用才有 Dock 图标和菜单栏
        NSApp.setActivationPolicy(.regular)
        // 浏览器用 open -g 在后台拉起，不抢焦点
        if !launchedByURL { NSApp.activate() }
        store.start()
    }

    private var launchedByURL = false

    func application(_ application: NSApplication, open urls: [URL]) {
        launchedByURL = true
        for url in urls { store.handle(url) }
    }

    /// 菜单栏图标开着时关窗口不退出，下载继续
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !store.settings.menuBar }
}
