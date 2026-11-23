// 探测 HTTP 资源，调度分段下载和断点续传。
import Foundation

public struct DownloadJob: Sendable {
    public var url: URL
    public var destination: URL
    public var segments: Int

    public init(url: URL, destination: URL, segments: Int = 0) {
        self.url = url
        self.destination = destination
        self.segments = segments
    }
}

public struct DownloadProgress: Sendable {
    public var received: Int64
    public var total: Int64?
}

enum EngineError: LocalizedError, Equatable {
    case status(Int), invalidResponse, incomplete, busy, backgroundSession
    case restart

    var errorDescription: String? {
        switch self {
        case .status(let code): "服务器返回 \(code)"
        case .invalidResponse: "服务器返回了无效的下载响应"
        case .incomplete: "下载数据长度不符"
        case .busy: "该文件正在下载"
        case .backgroundSession: "下载引擎需要前台 URLSession"
        case .restart: "服务器已更改下载范围"
        }
    }
}

struct EngineResource: Codable, Equatable {
    let url: URL
    let total: Int64?
    let etag: String?
    let lastModified: String?

    init(_ url: URL, _ response: HTTPURLResponse, probedLength: Int64? = nil) {
        self.url = url
        let length = response.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init)
        // 206 的 Content-Length 只表示响应片段大小。
        let fullLength = response.statusCode == 206 ? probedLength : (length ?? probedLength)
        total = response.hasIdentityEncoding ? fullLength.flatMap { $0 >= 0 ? $0 : nil } : nil
        etag = response.value(forHTTPHeaderField: "ETag")
        lastModified = response.value(forHTTPHeaderField: "Last-Modified")
    }

    var ifRange: String? {
        if let etag, !etag.hasPrefix("W/") { return etag }
        return lastModified
    }

    func acceptsValidators(_ response: HTTPURLResponse) -> Bool {
        for (field, expected) in [("ETag", etag), ("Last-Modified", lastModified)] {
            if let expected, let actual = response.value(forHTTPHeaderField: field), expected != actual {
                return false
            }
        }
        return true
    }
}

private extension HTTPURLResponse {
    var hasIdentityEncoding: Bool {
        let encoding = value(forHTTPHeaderField: "Content-Encoding")?.lowercased()
        return encoding == nil || encoding == "identity"
    }
}

public enum DownloadEngine {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var destinations: Set<URL> = []

    /// 取消任务即暂停。用相同的目标路径再次运行即可续传。
    public static func run(_ job: DownloadJob, session: URLSession = .shared,
                           onProgress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {
        try Task.checkCancellation()
        guard session.configuration.identifier == nil else { throw EngineError.backgroundSession }
        let path = job.destination.standardizedFileURL
        guard lock.withLock({ destinations.insert(path).inserted }) else { throw EngineError.busy }
        defer { _ = lock.withLock { destinations.remove(path) } }

        do {
            let (resource, ranges) = try await probe(job.url, session)
            let file = try EngineFile(job, resource: resource, ranged: ranges, progress: onProgress)
            do {
                try await download(job.url, resource, file, session)
            } catch {
                // 任务组已收齐所有回调，此时保存的偏移不会再变。
                try file.checkpoint()
                throw error
            }
            return try file.finish(at: job.destination)
        } catch {
            try Task.checkCancellation()
            throw error
        }
    }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return request
    }

    private static func checked(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw EngineError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw EngineError.status(http.statusCode) }
        return http
    }

    private static func probe(_ url: URL, _ session: URLSession) async throws -> (EngineResource, Bool) {
        var head = request(url)
        head.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: head)
        guard let http = response as? HTTPURLResponse else { throw EngineError.invalidResponse }
        if (200..<300).contains(http.statusCode), let ranges = http.value(forHTTPHeaderField: "Accept-Ranges") {
            return (EngineResource(url, http), ranges.lowercased() == "bytes")
        }

        var sample = request(url)
        sample.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (bytes, headers) = try await session.bytes(for: sample)
        bytes.task.cancel()  // 只取响应头，服务器可能忽略 Range 并发送整个文件。
        try Task.checkCancellation()
        let sampled = try checked(headers)
        guard sampled.statusCode == 206 else { return (EngineResource(url, sampled), false) }
        let prefix = "bytes 0-0/"
        guard let range = sampled.value(forHTTPHeaderField: "Content-Range")?.lowercased(),
              range.hasPrefix(prefix) else { throw EngineError.invalidResponse }
        let length = range.dropFirst(prefix.count)
        if length == "*" { return (EngineResource(url, sampled), false) }
        guard let total = Int64(length), total > 0 else { throw EngineError.invalidResponse }
        return (EngineResource(url, sampled, probedLength: total), true)
    }

    private static func download(_ url: URL, _ resource: EngineResource,
                                 _ file: EngineFile, _ session: URLSession) async throws {
        let segments = file.segments
        if segments.first?.end != nil {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for (index, segment) in segments.enumerated() {
                        guard let end = segment.end, segment.next < end else { continue }
                        group.addTask {
                            try await downloadRange(segment.next..<end, index, resource, file, session)
                        }
                    }
                    while let _ = try await group.next() {}
                }
                return
            } catch EngineError.restart {
                // 等所有分段停止后才能截断旧文件。
            }
        }
        try Task.checkCancellation()
        try await EngineTransfer.run(request(url), session: session) { response in
            let http = try checked(response)
            guard http.statusCode != 206 else { throw EngineError.invalidResponse }
            let length = resource.acceptsValidators(http) ? resource.total : nil
            try file.beginFullDownload(EngineResource(url, http, probedLength: length))
        } receive: { try file.write($0, to: 0) }
        try file.verify(0)
    }

    private static func downloadRange(_ range: Range<Int64>, _ index: Int, _ resource: EngineResource,
                                      _ file: EngineFile, _ session: URLSession) async throws {
        var req = request(resource.url)
        let bounds = "\(range.lowerBound)-\(range.upperBound - 1)"
        req.setValue("bytes=\(bounds)", forHTTPHeaderField: "Range")
        req.setValue(resource.ifRange, forHTTPHeaderField: "If-Range")
        try await EngineTransfer.run(req, session: session) { response in
            let http = try checked(response)
            guard http.statusCode != 200, resource.acceptsValidators(http) else { throw EngineError.restart }
            guard http.statusCode == 206, http.hasIdentityEncoding, let total = resource.total,
                  http.value(forHTTPHeaderField: "Content-Range")?.lowercased() == "bytes \(bounds)/\(total)"
            else { throw EngineError.invalidResponse }
        } receive: { try file.write($0, to: index) }
        try file.verify(index)
    }
}
