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

    public static func eta(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds.rounded(.up))) 秒" }
        if seconds < 3600 { return "\(Int((seconds / 60).rounded(.up))) 分" }
        return String(format: "%.1f 小时", seconds / 3600)
    }

    /// 任务行第三层的灰色小字
    public static func summary(_ item: DownloadItem) -> String {
        let total = bytes(Double(item.size))
        let progress = "\(bytes(Double(item.received))) / \(total)"
        switch item.status {
        case .downloading:
            if let message = item.message { return "\(message) · \(progress)" }
            // 服务器没给长度时只能显示已下多少
            guard item.size > 0 else { return "\(bytes(item.speed))/s · 已下 \(bytes(Double(item.received)))" }
            let remaining = Double(item.size - item.received) / max(item.speed, 1)
            return "\(bytes(item.speed))/s · 剩 \(eta(remaining)) · \(progress)"
        case .queued: return "排队中 · \(total)"
        case .paused: return "已暂停 · \(progress)"
        case .failed: return "\(item.message ?? "连接中断") · \(progress)"
        case .completed: return "\(total) · \(item.category.displayName)"
        }
    }
}
