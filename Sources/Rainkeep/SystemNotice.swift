// 系统通知：申请权限、发「下载完成」
import Foundation
import UserNotifications

enum SystemNotice {
    /// swift run 直接跑可执行文件时没有 app 包，系统通知用不了，只留应用内提示
    private static var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestPermission() {
        guard canNotify else { return }
        // 用户拒绝也没关系，下载完成时还有应用内提示
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ title: String, body: String) {
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
