// 调度：按上限排队、驱动下载引擎、网络类错误退避重试、算速度、完成和失败的收尾
import Foundation
import RainkeepCore

extension DownloadStore {
    /// 等待重试时多久看一眼网络是否恢复
    private static let retryPollInterval = Duration.milliseconds(500)
    private static let speedSmoothing = 0.3
    private static let minSpeedSampleSeconds = 0.2

    /// 按上限排好下载/排队，再让正在跑的引擎任务和状态对上，最后存盘
    func reschedule() {
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
        if let name = progress.serverName { serverNames[id] = name }
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
        adoptServerName(id)
        let resorted = settings.learn ? resort(id) : nil
        relocate(id)
        if let resorted {
            showToast(sortedMessage(resorted))
        } else if settings.notify, let name = items.first(where: { $0.id == id })?.name {
            showToast(language.pick("下载完成：", "Downloaded: ") + name)
            SystemNotice.post(language.pick("下载完成", "Download complete"), body: name)
        }
        reschedule()
    }

    /// 名字是从链接猜的（比如 download.php），下完换成服务器给的名字，并挪进新类型对应的文件夹
    private func adoptServerName(_ id: UUID) {
        guard let name = serverNames.removeValue(forKey: id),
              let i = items.firstIndex(where: { $0.id == id }), items[i].guessedName == true,
              let source = items[i].destination else { return }
        items[i].guessedName = nil
        var renamed = items[i]
        renamed.name = name
        let dir = directory(for: renamed)
        // 自己占着的名字不算重名，免得 a (1).zip 又被改成 a (2).zip
        let taken = takenNames(in: dir).subtracting(dir.path == source.deletingLastPathComponent().path ? [source.lastPathComponent] : [])
        let target = dir.appending(path: Naming.uniqueName(name, taken: taken))
        guard target.path != source.path else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: source, to: target)
            items[i].name = target.lastPathComponent
            items[i].destination = target
        } catch {
            showToast(language.pick("改名失败：", "Couldn't rename the file: ") + error.localizedDescription)
        }
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
}
