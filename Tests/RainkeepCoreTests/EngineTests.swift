// 本地协议模拟 HTTP 响应，每个用例独占 URL、会话和临时目录。
import Foundation
import Testing
@testable import RainkeepCore

private struct Reply {
    var body: Data
    var etag = "\"v1\""
    var lastModified = "Sun, 01 Nov 2026 00:00:00 GMT"
    var ranges = true
    var ignoreRange = false
    var knownLength = true
    var stall = false
    var status = 200
    var headStatus: Int?
    var omitAcceptRanges = false
    var pauseAfterBytes: [Int: Int] = [:]
    var badContentRange = false
}

private final class Server: @unchecked Sendable {
    private let lock = NSLock()
    private var reply: Reply
    private var requests: [URLRequest] = []
    private var held: [Int: EngineProtocol] = [:]

    init(_ reply: Reply) { self.reply = reply }

    func record(_ request: URLRequest) -> Reply {
        lock.withLock {
            requests.append(request)
            return reply
        }
    }

    func hold(_ request: EngineProtocol, at start: Int) { lock.withLock { held[start] = request } }

    func heldRequest(at start: Int) throws -> EngineProtocol {
        try #require(lock.withLock { held[start] })
    }

    func change(_ edit: (inout Reply) -> Void) {
        lock.withLock {
            edit(&reply)
            requests.removeAll()
        }
    }

    var allRequests: [URLRequest] { lock.withLock { requests } }
    var gets: [URLRequest] { allRequests.filter { $0.httpMethod == "GET" } }
}

private final class EngineProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var servers: [URL: Server] = [:]

    static func register(_ server: Server?, at url: URL) { lock.withLock { servers[url] = server } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let server = Self.lock.withLock({ Self.servers[url] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let reply = server.record(request)
        let total = reply.body.count
        var bytes = 0..<total
        let isHead = request.httpMethod == "HEAD"
        var status = isHead ? (reply.headStatus ?? reply.status) : reply.status
        var headers = ["Accept-Ranges": reply.ranges ? "bytes" : "none",
                       "ETag": reply.etag, "Last-Modified": reply.lastModified]
        if reply.omitAcceptRanges { headers.removeValue(forKey: "Accept-Ranges") }
        if status == 200, reply.ranges, !reply.ignoreRange,
           let range = request.value(forHTTPHeaderField: "Range") {
            let bounds = range.dropFirst("bytes=".count).split(separator: "-")
            guard range.hasPrefix("bytes="), bounds.count == 2, let lo = Int(bounds[0]),
                  let hi = Int(bounds[1]), lo >= 0, lo <= hi, hi < total else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            bytes = lo..<(hi + 1)
            status = 206
            headers["Content-Range"] = "bytes \(reply.badContentRange ? lo + 1 : lo)-\(hi)/\(total)"
        }
        if reply.knownLength { headers["Content-Length"] = String(bytes.count) }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !isHead, status < 300 {
            // 探测若等待正文，会在此挂起直到会话超时。
            if status == 200, request.value(forHTTPHeaderField: "Range") == "bytes=0-0" {
                client?.urlProtocol(self, didLoad: reply.body.prefix(4096))
                return
            }
            let prefix = status == 206 ? reply.pauseAfterBytes[bytes.lowerBound] : nil
            if let prefix {
                server.hold(self, at: bytes.lowerBound)
                bytes = bytes.prefix(prefix)
            } else if reply.stall { bytes = bytes.prefix(bytes.count / 2) }
            for offset in stride(from: bytes.lowerBound, to: bytes.upperBound, by: 256 * 1024) {
                let end = min(offset + 256 * 1024, bytes.upperBound)
                client?.urlProtocol(self, didLoad: reply.body.subdata(in: offset..<end))
            }
            if reply.stall || prefix != nil { return }
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    func send(_ data: Data, finish: Bool = true) {
        client?.urlProtocol(self, didLoad: data)
        if finish { client?.urlProtocolDidFinishLoading(self) }
    }
}

private let mib = 1 << 20

private func payload(_ count: Int) -> Data {
    // 周期和段大小互质，写错段偏移也能测出来。
    let pattern = Data((0..<65_521).map { UInt8(truncatingIfNeeded: $0 ^ ($0 >> 8)) })
    var data = Data(capacity: count)
    while data.count < count { data.append(pattern.prefix(count - data.count)) }
    return data
}

private struct Fixture {
    let job: DownloadJob
    let server: Server
    let session: URLSession
    var part: URL { job.destination.appendingPathExtension("part") }
    var manifest: URL { part.appendingPathExtension("json") }

    @discardableResult
    func run(_ progress: @escaping @Sendable (DownloadProgress) -> Void = { _ in }) async throws -> URL {
        try await DownloadEngine.run(job, session: session, onProgress: progress)
    }

    func checkResult(_ expected: Data) throws {
        let result = try Data(contentsOf: job.destination)
        #expect(result == expected)
        #expect(!FileManager.default.fileExists(atPath: part.path))
        #expect(!FileManager.default.fileExists(atPath: manifest.path))
    }

    func waitForWrites(_ ranges: [Range<Int>], from source: Data) async throws {
        // 稀疏文件的长度可能已经很大，要确认每一段的数据实际写入。
        let deadline = ContinuousClock.now + .seconds(5)
        var ready = false
        while ContinuousClock.now < deadline {
            if FileManager.default.fileExists(atPath: part.path) {
                let partial = try Data(contentsOf: part)
                ready = ranges.allSatisfy { $0.upperBound <= partial.count && partial[$0] == source[$0] }
                if ready { break }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(ready)
    }

    func pause(whenWritten ranges: [Range<Int>], from source: Data) async throws {
        let task = Task { try await run() }
        defer { task.cancel() }
        try await waitForWrites(ranges, from: source)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(FileManager.default.fileExists(atPath: part.path))
        #expect(FileManager.default.fileExists(atPath: manifest.path))
        #expect(!FileManager.default.fileExists(atPath: job.destination.path))
    }
}

private func withServer(_ reply: Reply, segments: Int = 0,
                        test: (Fixture) async throws -> Void) async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
    let url = URL(string: "https://engine.invalid/\(UUID().uuidString)")!
    let job = DownloadJob(url: url, destination: dir.appendingPathComponent("result"), segments: segments)
    let server = Server(reply)
    EngineProtocol.register(server, at: url)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [EngineProtocol.self]
    config.timeoutIntervalForResource = 10
    let session = URLSession(configuration: config)
    defer {
        session.invalidateAndCancel()
        EngineProtocol.register(nil, at: url)
    }
    do {
        try await test(Fixture(job: job, server: server, session: session))
    } catch {
        try FileManager.default.removeItem(at: dir)
        throw error
    }
    try FileManager.default.removeItem(at: dir)
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var update: DownloadProgress?
    func append(_ value: DownloadProgress) { lock.withLock { update = value } }
    var last: DownloadProgress? { lock.withLock { update } }
}

@Test func concurrentRangesAssemble50MiB() async throws {
    let data = payload(50 * mib + 3)
    try await withServer(Reply(body: data)) { fixture in
        let log = ProgressLog()
        let destination = try await fixture.run(log.append)
        #expect(destination == fixture.job.destination)
        let ranges = fixture.server.gets.compactMap { $0.value(forHTTPHeaderField: "Range") }
        let size = data.count / 4
        for index in 0..<4 {
            let end = index == 3 ? data.count : (index + 1) * size
            #expect(ranges.contains("bytes=\(index * size)-\(end - 1)"))
        }
        #expect(log.last?.received == Int64(data.count))
        #expect(log.last?.total == Int64(data.count))
        try fixture.checkResult(data)
    }
}

@Test func resumesBothRangesFromSavedOffsets() async throws {
    let data = payload(4 * mib)
    try await withServer(Reply(body: data, stall: true), segments: 2) { fixture in
        try await fixture.pause(whenWritten: [0..<mib, (2 * mib)..<(3 * mib)], from: data)
        fixture.server.change { $0.stall = false }
        try await fixture.run()
        let gets = fixture.server.gets
        let ranges = gets.compactMap { $0.value(forHTTPHeaderField: "Range") }.sorted()
        #expect(ranges == ["bytes=\(mib)-\(2 * mib - 1)", "bytes=\(3 * mib)-\(4 * mib - 1)"])
        #expect(gets.count == 2)
        #expect(gets.allSatisfy { $0.value(forHTTPHeaderField: "If-Range") == "\"v1\"" })
        try fixture.checkResult(data)
    }
}

@Test(arguments: [false, true])
private func splitsLargestRemainingRange(pauseAfterSplit: Bool) async throws {
    let size = 4 * mib
    let data = payload(3 * size)
    let slowPrefix = mib + 1
    let reply = Reply(body: data, pauseAfterBytes: [0: 3 * mib, size: slowPrefix, 2 * size: mib])
    try await withServer(reply, segments: 3) { fixture in
        let task = Task { try await fixture.run() }
        defer { task.cancel() }
        let next = size + slowPrefix
        let midpoint = next + (2 * size - next) / 2
        try await fixture.waitForWrites([0..<(3 * mib), size..<next, (2 * size)..<(2 * size + mib)], from: data)
        try fixture.server.heldRequest(at: 2 * size).send(data.suffix(from: 2 * size + mib))
        try await fixture.waitForWrites([midpoint..<(2 * size)], from: data)
        #expect(fixture.server.gets.count == 4)
        #expect(fixture.server.gets.last?.value(forHTTPHeaderField: "Range") == "bytes=\(midpoint)-\(2 * size - 1)")

        if pauseAfterSplit {
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
            fixture.server.change { $0.pauseAfterBytes = [:] }
            try await fixture.run()
            let ranges = fixture.server.gets.compactMap { $0.value(forHTTPHeaderField: "Range") }
            #expect(Set(ranges) == ["bytes=\(3 * mib)-\(size - 1)", "bytes=\(next)-\(midpoint - 1)"])
        } else {
            // 越界部分故意发错且不结束响应，只有截断写入并取消原请求才能通过。
            let crossing = data.subdata(in: next..<midpoint) + Data(repeating: 0, count: 1024)
            try fixture.server.heldRequest(at: size).send(crossing, finish: false)
            try fixture.server.heldRequest(at: 0).send(data.subdata(in: (3 * mib)..<size))
            _ = try await task.value
        }
        try fixture.checkResult(data)
    }
}

@Test(arguments: [2, 17])
private func resumesManifestWithOriginalFields(segmentCount: Int) async throws {
    let size = mib
    let data = payload(segmentCount * size)
    try await withServer(Reply(body: data), segments: 1) { fixture in
        var partial = Data(repeating: 0, count: data.count)
        var segments: [[String: Int]] = []
        var expected = Set<String>()
        for index in 0..<segmentCount {
            let start = index * size, end = start + size, next = start + size / 2
            partial[start..<next] = data[start..<next]
            segments.append(["start": start, "next": next, "end": end])
            expected.insert("bytes=\(next)-\(end - 1)")
        }
        // 旧记录按起点排序，追加过新段的记录可能乱序且超过原并发上限。
        if segmentCount > 2 { segments.swapAt(1, segmentCount - 1) }
        let resource: [String: Any] = ["url": fixture.job.url.absoluteString, "total": data.count,
                                       "etag": "\"v1\"", "lastModified": "Sun, 01 Nov 2026 00:00:00 GMT"]
        try partial.write(to: fixture.part)
        try JSONSerialization.data(withJSONObject: ["resource": resource, "segments": segments]).write(to: fixture.manifest)
        try await fixture.run()
        let ranges = fixture.server.gets.compactMap { $0.value(forHTTPHeaderField: "Range") }
        #expect(Set(ranges) == expected)
        #expect(ranges.count == expected.count)
        try fixture.checkResult(data)
    }
}

@Test func leavesSmallRemaindersIntact() async throws {
    let prefix = mib / 4
    let size = Int(EngineSegment.minimumSplitSize) - 1 + prefix
    let data = payload(2 * size)
    try await withServer(Reply(body: data, pauseAfterBytes: [0: prefix, size: prefix]), segments: 2) { fixture in
        let task = Task { try await fixture.run() }
        defer { task.cancel() }
        try await fixture.waitForWrites([0..<prefix, size..<(size + prefix)], from: data)
        try fixture.server.heldRequest(at: 0).send(data.subdata(in: prefix..<size))
        try await fixture.waitForWrites([prefix..<size], from: data)
        try fixture.server.heldRequest(at: size).send(data.suffix(from: size + prefix))
        _ = try await task.value
        #expect(fixture.server.gets.count == 2)
        try fixture.checkResult(data)
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}

@Test(arguments: [false, true])
private func fullDownloadWithoutUsableRanges(knownLength: Bool) async throws {
    let data = payload(2 * mib)
    try await withServer(Reply(body: data, ranges: !knownLength, knownLength: knownLength, stall: true)) { fixture in
        try await fixture.pause(whenWritten: [0..<mib], from: data)
        fixture.server.change { $0.stall = false }
        let log = ProgressLog()
        try await fixture.run(log.append)
        let request = try #require(fixture.server.gets.only)
        #expect(request.value(forHTTPHeaderField: "Range") == nil)
        #expect(log.last?.received == Int64(data.count))
        #expect(log.last?.total == (knownLength ? Int64(data.count) : nil))
        try fixture.checkResult(data)
    }
}

private enum Change: CaseIterable, Sendable { case etag, date, size }

@Test(arguments: Change.allCases)
private func changedResourceRestarts(_ change: Change) async throws {
    let old = Data(repeating: 7, count: 2 * mib)
    let new = payload(old.count + (change == .size ? 1 : 0))
    try await withServer(Reply(body: old, stall: true), segments: 1) { fixture in
        try await fixture.pause(whenWritten: [0..<mib], from: old)
        fixture.server.change {
            $0.body = new
            $0.stall = false
            if change == .etag { $0.etag = "\"v2\"" }
            if change == .date { $0.lastModified = "Mon, 02 Nov 2026 00:00:00 GMT" }
        }
        try await fixture.run()
        let request = try #require(fixture.server.gets.only)
        #expect(request.value(forHTTPHeaderField: "Range") == "bytes=0-\(new.count - 1)")
        try fixture.checkResult(new)
    }
}

@Test func ignoredRangeRestartsAsSingleGET() async throws {
    let data = payload(2 * mib)
    try await withServer(Reply(body: data, ignoreRange: true), segments: 2) { fixture in
        try await fixture.run()
        let gets = fixture.server.gets
        #expect(gets.contains { $0.value(forHTTPHeaderField: "Range") != nil })
        #expect(gets.filter { $0.value(forHTTPHeaderField: "Range") == nil }.count == 1)
        try fixture.checkResult(data)
    }
}

@Test func httpErrorHasUserFacingMessage() async throws {
    try await withServer(Reply(body: Data(), status: 404)) { fixture in
        do {
            try await fixture.run()
            Issue.record("404 应抛出错误")
        } catch {
            #expect(error.localizedDescription == "服务器返回 404")
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.job.destination.path))
    }
}

@Test func rejectsWrongContentRange() async throws {
    try await withServer(Reply(body: payload(mib), badContentRange: true)) { fixture in
        await #expect(throws: EngineError.invalidResponse) { try await fixture.run() }
        #expect(!FileManager.default.fileExists(atPath: fixture.job.destination.path))
    }
}

@Test(arguments: [200, 403, 405])
private func rangeProbeFindsSegmentSupport(headStatus: Int) async throws {
    let data = payload(2 * mib)
    try await withServer(Reply(body: data, headStatus: headStatus, omitAcceptRanges: headStatus == 200), segments: 2) { fixture in
        try await fixture.run()
        let ranges = fixture.server.gets.compactMap { $0.value(forHTTPHeaderField: "Range") }
        #expect(ranges.first == "bytes=0-0")
        #expect(Set(ranges.dropFirst()) == ["bytes=0-1048575", "bytes=1048576-2097151"])
        try fixture.checkResult(data)
    }
}

@Test func ignoredProbeStartsFullGETWithoutWaitingForBody() async throws {
    let data = payload(mib)
    try await withServer(Reply(body: data, ignoreRange: true, headStatus: 405)) { fixture in
        try await fixture.run()
        let ranges = fixture.server.gets.map { $0.value(forHTTPHeaderField: "Range") }
        #expect(ranges == ["bytes=0-0", nil])
        try fixture.checkResult(data)
    }
}

@Test func connectionLossResumesInterruptedSegment() async throws {
    let data = payload(2 * mib)
    try await withServer(Reply(body: data, pauseAfterBytes: [mib: mib / 2]), segments: 2) { fixture in
        let task = Task { try await fixture.run() }
        defer { task.cancel() }
        try await fixture.waitForWrites([mib..<(mib + mib / 2)], from: data)
        let request = try fixture.server.heldRequest(at: mib)
        request.client?.urlProtocol(request, didFailWithError: URLError(.networkConnectionLost))
        let error = await #expect(throws: URLError.self) { try await task.value }
        #expect(error?.code == .networkConnectionLost)
        #expect(FileManager.default.fileExists(atPath: fixture.manifest.path))
        fixture.server.change { $0.pauseAfterBytes = [:] }
        try await fixture.run()
        let ranges = fixture.server.gets.compactMap { $0.value(forHTTPHeaderField: "Range") }
        #expect(ranges.contains("bytes=\(mib + mib / 2)-\(2 * mib - 1)"))
        try fixture.checkResult(data)
    }
}

/// HEAD、首字节探测、分段及回退 GET 都应携带自定义头，并保留引擎的范围控制。
@Test(arguments: [false, true])
func customHeadersReachEveryRequest(ignoreRange: Bool) async throws {
    let data = payload(2 * mib)
    try await withServer(Reply(body: data, ignoreRange: ignoreRange, headStatus: 405), segments: 2) { fixture in
        var job = fixture.job
        job.headers = ["X-Download": "ticket", "Cookie": "session=example", "rAnGe": "bytes=7-9",
                       "IF-range": "wrong", "aCCept-encoding": "gzip"]
        _ = try await DownloadEngine.run(job, session: fixture.session) { _ in }
        let requests = fixture.server.allRequests
        #expect(requests.first?.httpMethod == "HEAD")
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Download") == "ticket" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == "session=example" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Accept-Encoding") == "identity" })
        let ranges = requests.map { $0.value(forHTTPHeaderField: "Range") }
        #expect(Array(ranges.prefix(2)) == [nil, "bytes=0-0"])
        #expect(requests.prefix(2).allSatisfy { $0.value(forHTTPHeaderField: "If-Range") == nil })
        if ignoreRange {
            #expect(Array(ranges.dropFirst(2)) == [nil])
            #expect(requests.last?.value(forHTTPHeaderField: "If-Range") == nil)
        } else {
            #expect(Set(ranges.dropFirst(2)) == ["bytes=0-1048575", "bytes=1048576-2097151"])
            #expect(requests.dropFirst(2).allSatisfy { $0.value(forHTTPHeaderField: "If-Range") == "\"v1\"" })
        }
        try fixture.checkResult(data)
    }
}
