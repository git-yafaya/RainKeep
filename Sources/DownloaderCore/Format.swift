// 界面上显示的大小、剩余时间和任务小字
import Foundation

public enum Format {
    public static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var amount = value
        var i = 0
        while amount >= 1024 && i < units.count - 1 {
            amount /= 1024
            i += 1
        }
        return String(format: i < 2 ? "%.0f %@" : "%.1f %@", amount, units[i])
    }

    public static func eta(_ seconds: Double, _ language: Language = .zh) -> String {
        if seconds < 60 { return "\(Int(seconds.rounded(.up))) \(language.pick("秒", "s"))" }
        if seconds < 3600 { return "\(Int((seconds / 60).rounded(.up))) \(language.pick("分", "min"))" }
        return String(format: "%.1f %@", seconds / 3600, language.pick("小时", "h"))
    }

    /// 任务行第三层的灰色小字；已完成的显示自定义分类名，没有就显示类型
    public static func summary(_ item: DownloadItem, _ language: Language = .zh, groupName: String? = nil) -> String {
        let l = language
        let total = bytes(Double(item.size))
        let progress = "\(bytes(Double(item.received))) / \(total)"
        switch item.status {
        case .downloading:
            if let message = item.message { return "\(message) · \(progress)" }
            // 服务器没给长度时只能显示已下多少
            guard item.size > 0 else { return "\(bytes(item.speed))/s · \(l.pick("已下", "got")) \(bytes(Double(item.received)))" }
            let remaining = Double(item.size - item.received) / max(item.speed, 1)
            return "\(bytes(item.speed))/s · \(l.pick("剩 ", ""))\(eta(remaining, l))\(l.pick("", " left")) · \(progress)"
        case .queued: return "\(l.pick("排队中", "Queued")) · \(total)"
        case .paused: return "\(l.pick("已暂停", "Paused")) · \(progress)"
        case .failed: return "\(item.message ?? l.pick("连接中断", "Connection lost")) · \(progress)"
        case .completed: return "\(total) · \(groupName ?? item.category.name(l))"
        }
    }
}
