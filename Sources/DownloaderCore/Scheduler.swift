// 并发调度：控制同时下载的任务数
import Foundation

public enum Scheduler {
    /// 让下载中的任务数等于上限：超出的退回排队，空位按列表顺序从排队里补
    public static func schedule(_ items: inout [DownloadItem], maxActive: Int) {
        var active = 0
        for i in items.indices where items[i].status == .downloading {
            if active < maxActive {
                active += 1
            } else {
                items[i].status = .queued
                items[i].speed = 0
            }
        }
        for i in items.indices where items[i].status == .queued && active < maxActive {
            items[i].status = .downloading
            active += 1
        }
    }
}
