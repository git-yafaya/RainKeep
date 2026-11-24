// 按偏移写入临时文件，保存续传状态并交付最终文件。
import Foundation

struct EngineSegment: Codable {
    let start: Int64
    var next: Int64
    let end: Int64?  // 右开边界，单连接下载没有分段边界

    static let full = Self(start: 0, next: 0, end: nil)

    static func split(total: Int64?, requested: Int, ranged: Bool) -> [Self] {
        guard ranged, let total, total > 0 else { return [.full] }
        let mib: Int64 = 1 << 20
        let wanted = requested == 0 ? (total < 4 * mib ? 1 : 4) : requested
        let count = max(1, min(Int64(wanted), 16, total / mib))
        let size = total / count
        return (0..<count).map { index in
            let start = index * size
            return Self(start: start, next: start, end: index == count - 1 ? total : start + size)
        }
    }
}

private struct EngineState: Codable {
    let resource: EngineResource
    var segments: [EngineSegment]

    func canResume(_ current: EngineResource, fileSize: Int64) -> Bool {
        guard resource == current, let total = current.total, fileSize <= total,
              (1...16).contains(segments.count) else { return false }
        var boundary: Int64 = 0
        for segment in segments {
            guard segment.start == boundary, let end = segment.end, end > boundary, end <= total,
                  (boundary...end).contains(segment.next),
                  segment.next == boundary || segment.next <= fileSize else { return false }
            boundary = end
        }
        return boundary == total
    }
}

// 同一把锁保护共享文件偏移、续传记录和进度回调的顺序。
final class EngineFile: @unchecked Sendable {
    private let part: URL
    private let manifest: URL
    private let handle: FileHandle
    private let lock = NSLock()
    private let progress: @Sendable (DownloadProgress) -> Void
    private var state: EngineState
    private var lastProgress: ContinuousClock.Instant?
    private var lastSave = ContinuousClock.now

    var segments: [EngineSegment] { lock.withLock { state.segments } }

    init(_ job: DownloadJob, resource: EngineResource, ranged: Bool,
         progress: @escaping @Sendable (DownloadProgress) -> Void) throws {
        part = job.destination.appendingPathExtension("part")
        manifest = part.appendingPathExtension("json")
        self.progress = progress
        let plan = EngineSegment.split(total: resource.total, requested: job.segments, ranged: ranged)
        state = EngineState(resource: resource, segments: plan)

        let exists = FileManager.default.fileExists(atPath: part.path)
        if !exists { try Data().write(to: part, options: .withoutOverwriting) }
        handle = try FileHandle(forWritingTo: part)
        if exists, plan.first?.end != nil, FileManager.default.fileExists(atPath: manifest.path) {
            let data = try Data(contentsOf: manifest)
            let size = try handle.seekToEnd()
            // 损坏的记录无法证明哪些字节有效，只能重新下载。
            if let saved = try? JSONDecoder().decode(EngineState.self, from: data),
               let size = Int64(exactly: size), saved.canResume(resource, fileSize: size) {
                state = saved
                return
            }
        }
        try handle.truncate(atOffset: 0)
        try checkpoint()
    }

    func beginFullDownload(_ resource: EngineResource) throws {
        try lock.withLock {
            state = EngineState(resource: resource, segments: [.full])
            try handle.truncate(atOffset: 0)
            try save()
        }
    }

    func write(_ data: Data, to index: Int) throws {
        try lock.withLock {
            let segment = state.segments[index]
            let (next, overflow) = segment.next.addingReportingOverflow(Int64(data.count))
            guard !overflow, next <= (segment.end ?? state.resource.total ?? Int64.max) else {
                throw EngineError.incomplete
            }
            try handle.seek(toOffset: UInt64(segment.next))
            try handle.write(contentsOf: data)
            state.segments[index].next = next
            let now = ContinuousClock.now
            if now - lastSave >= .seconds(2) { try save() }
            if lastProgress.map({ now - $0 >= .milliseconds(200) }) ?? true {
                lastProgress = now
                report()
            }
        }
    }

    func verify(_ index: Int) throws {
        try lock.withLock {
            let segment = state.segments[index]
            if let end = segment.end ?? state.resource.total, segment.next != end {
                throw EngineError.incomplete
            }
        }
    }

    func checkpoint() throws {
        try lock.withLock { try save() }
    }

    private func save() throws {
        try handle.synchronize()
        try JSONEncoder().encode(state).write(to: manifest, options: .atomic)
        lastSave = .now
    }

    func finish(at destination: URL) throws -> URL {
        try checkpoint()
        try handle.close()
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: part, to: destination)
        try FileManager.default.removeItem(at: manifest)
        lock.withLock { report() }
        return destination
    }

    private func report() {
        let received = state.segments.reduce(Int64(0)) { $0 + ($1.next - $1.start) }
        progress(DownloadProgress(received: received, total: state.resource.total))
    }
}
