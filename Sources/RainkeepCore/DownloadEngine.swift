// 探测 HTTP 资源，调度分段下载和断点续传。
import Foundation

public struct DownloadJob: Sendable {
    public var url: URL
    public var destination: URL
    public var segments: Int
    public var headers: [String: String]

    /// 创建下载任务，可附带浏览器提供的请求头。
    public init(url: URL, destination: URL, segments: Int = 0, headers: [String: String] = [:]) {
        self.url = url
        self.destination = destination
        self.segments = segments
        self.headers = headers
    }
}

public struct DownloadProgress: Sendable {
    public var received: Int64
    public var total: Int64?
    /// 服务器在 Content-Disposition 里给的文件名，没给是 nil
    public var serverName: String?
}

public enum EngineError: LocalizedError, Equatable {
    case status(Int), invalidResponse, incomplete, busy, backgroundSession
    case restart

    /// 按界面语言给出原因，任务行和更新检测失败时显示
    public func message(_ language: Language) -> String {
        switch self {
        case .status(let code): language.pick("服务器返回错误（\(code)）", "Server returned \(code)")
        case .invalidResponse: language.pick("服务器响应无效", "Invalid response from server")
        case .incomplete: language.pick("文件大小与服务器声明不符", "Download size mismatch")
        case .busy: language.pick("该文件已在下载列表中", "This file is already downloading")
        case .backgroundSession: language.pick("当前下载模式不可用（需前台会话）", "Download engine requires an active session")
        case .restart: language.pick("服务器不支持断点续传或范围已变更", "Server changed the download range")
        }
    }

    public var errorDescription: String? { message(.system) }
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
            let (resource, ranges, serverName) = try await probe(job, session)
            let file = try EngineFile(job, resource: resource, ranged: ranges) { progress in
                var progress = progress
                progress.serverName = serverName
                onProgress(progress)
            }
            do {
                try await download(job, resource, file, session)
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

    /// 探测和传输共用同一组头，范围和内容编码始终由引擎决定。
    private static func request(_ job: DownloadJob) -> URLRequest {
        var request = URLRequest(url: job.url, cachePolicy: .reloadIgnoringLocalCacheData)
        for (field, value) in job.headers {
            switch field.lowercased() {
            case "range", "if-range", "accept-encoding": continue
            default: request.setValue(value, forHTTPHeaderField: field)
            }
        }
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return request
    }

    private static func checked(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw EngineError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw EngineError.status(http.statusCode) }
        return http
    }

    /// 先用 HEAD 探测，必要时再请求首字节；顺带取服务器给的文件名。
    /// shortcut: 只看探测响应里的 Content-Disposition，HEAD 不带、只有正式 GET 才带的服务器取不到，遇到再改。
    private static func probe(_ job: DownloadJob, _ session: URLSession) async throws -> (EngineResource, Bool, String?) {
        var head = request(job)
        head.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: head)
        guard let http = response as? HTTPURLResponse else { throw EngineError.invalidResponse }
        let headName = (200..<300).contains(http.statusCode) ? serverName(http) : nil
        if (200..<300).contains(http.statusCode), let ranges = http.value(forHTTPHeaderField: "Accept-Ranges") {
            return (EngineResource(job.url, http), ranges.lowercased() == "bytes", headName)
        }

        var sample = request(job)
        sample.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (bytes, headers) = try await session.bytes(for: sample)
        bytes.task.cancel()  // 只取响应头，服务器可能忽略 Range 并发送整个文件。
        try Task.checkCancellation()
        let sampled = try checked(headers)
        let name = headName ?? serverName(sampled)
        guard sampled.statusCode == 206 else { return (EngineResource(job.url, sampled), false, name) }
        let prefix = "bytes 0-0/"
        guard let range = sampled.value(forHTTPHeaderField: "Content-Range")?.lowercased(),
              range.hasPrefix(prefix) else { throw EngineError.invalidResponse }
        let length = range.dropFirst(prefix.count)
        if length == "*" { return (EngineResource(job.url, sampled), false, name) }
        guard let total = Int64(length), total > 0 else { throw EngineError.invalidResponse }
        return (EngineResource(job.url, sampled, probedLength: total), true, name)
    }

    private static func serverName(_ response: HTTPURLResponse) -> String? {
        response.value(forHTTPHeaderField: "Content-Disposition").flatMap(Naming.fileName(fromDisposition:))
    }

    /// 调度各分段，服务器不支持范围时退回整文件下载。
    private static func download(_ job: DownloadJob, _ resource: EngineResource,
                                 _ file: EngineFile, _ session: URLSession) async throws {
        if file.rangeConcurrency > 0 {
            do {
                try await withThrowingTaskGroup(of: Int.self) { group in
                    var active = Set<Int>()
                    while true {
                        try Task.checkCancellation()
                        while active.count < file.rangeConcurrency, let work = file.claimRange(active: active) {
                            active.insert(work.index)
                            group.addTask {
                                try await downloadRange(work.range, work.index, request(job), resource, file, session)
                                return work.index
                            }
                        }
                        guard let finished = try await group.next() else { break }
                        active.remove(finished)
                    }
                }
                return
            } catch EngineError.restart {
                // 等所有分段停止后才能截断旧文件。
            }
        }
        try Task.checkCancellation()
        try await EngineTransfer.run(request(job), session: session) { response in
            let http = try checked(response)
            guard http.statusCode != 206 else { throw EngineError.invalidResponse }
            let length = resource.acceptsValidators(http) ? resource.total : nil
            try file.beginFullDownload(EngineResource(job.url, http, probedLength: length))
        } receive: { try file.write($0, to: 0) }
        try file.verify(0)
    }

    /// 为分段设置校验器并核对返回的字节区间。
    private static func downloadRange(_ range: Range<Int64>, _ index: Int, _ request: URLRequest,
                                      _ resource: EngineResource, _ file: EngineFile, _ session: URLSession) async throws {
        var req = request
        let bounds = "\(range.lowerBound)-\(range.upperBound - 1)"
        req.setValue("bytes=\(bounds)", forHTTPHeaderField: "Range")
        req.setValue(resource.ifRange, forHTTPHeaderField: "If-Range")
        // 每段单开一个会话：同一会话会把各段复用进一条 HTTP/2 连接，分段就失去了意义（Civitai 实测 4 段共用一条连接只有约 1/4 的速度）
        let rangeSession = URLSession(configuration: session.configuration)
        defer { rangeSession.finishTasksAndInvalidate() }
        try await EngineTransfer.run(req, session: rangeSession) { response in
            let http = try checked(response)
            guard http.statusCode != 200, resource.acceptsValidators(http) else { throw EngineError.restart }
            guard http.statusCode == 206, http.hasIdentityEncoding, let total = resource.total,
                  http.value(forHTTPHeaderField: "Content-Range")?.lowercased() == "bytes \(bounds)/\(total)"
            else { throw EngineError.invalidResponse }
        } receive: { try file.write($0, to: index, requestedEnd: range.upperBound) }
        try file.verify(index)
    }
}
