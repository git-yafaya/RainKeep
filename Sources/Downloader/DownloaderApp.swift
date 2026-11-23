// 应用入口：主窗口和菜单快捷键（⌘N 添加、⌘, 设置）
import AppKit
import SwiftUI

@main
struct DownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = DownloadStore.demo()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 720, minHeight: 440)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加下载…") { store.present(.add) }.keyboardShortcut("n")
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { store.present(.settings) }.keyboardShortcut(",")
            }
        }
    }
}

/// swift run 启动时没有 app 包，要手动设成普通前台应用才有 Dock 图标和菜单栏
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
