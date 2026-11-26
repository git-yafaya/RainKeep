// 读取一条 Native Messaging 消息，记录扩展连接或转交下载。
import AppKit
import Darwin
import RainkeepCore
import Foundation

private struct MessageHeader: Decodable {
    let type: String?
}

private struct Payload: Decodable {
    let url: URL
    let referrer: String?
    let filename: String?
    let cookies: String?
    let userAgent: String?
}

private struct Reply: Encodable {
    let ok: Bool
    var error: String?
}

private enum HostError: String, LocalizedError {
    case truncated = "消息未读完整"
    case size = "消息长度无效"
    case payload = "下载参数无效"
    case messageType = "不支持的消息类型"
    case open = "无法打开拾雨 App"

    var errorDescription: String? { rawValue }
}

/// 管道可能分次写入；读够当前帧即可，不等待 stdin 关闭。
private func readExactly(_ count: Int) throws -> Data {
    var data = Data()
    while data.count < count {
        guard let chunk = try FileHandle.standardInput.read(upToCount: count - data.count),
              !chunk.isEmpty else { throw HostError.truncated }
        data.append(chunk)
    }
    return data
}

private func parentBrowser() -> String? {
    // Swift 无法导入 PROC_PIDPATHINFO_MAXSIZE，沿用 SDK 的定义。
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let length = proc_pidpath(getppid(), &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    let path = FileManager.default.string(withFileSystemRepresentation: buffer, length: Int(length))
    let app = URL(fileURLWithPath: path).pathComponents.first { $0.hasSuffix(".app") }
    return app.map { String($0.dropLast(4)) }
}

@MainActor
private func handleMessage() async throws {
    let prefix = try readExactly(4)
    let length = prefix.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
    guard (1...1_048_576).contains(length) else { throw HostError.size }
    let body = try readExactly(Int(length))
    let decoder = JSONDecoder()
    let dryRun = ProcessInfo.processInfo.environment["RAINKEEP_HOST_DRY_RUN"] == "1"
    if let type = try decoder.decode(MessageHeader.self, from: body).type {
        guard type == "hello" else { throw HostError.messageType }
        if !dryRun {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: false)
            try ExtensionLink(browser: parentBrowser(), seen: Date()).save(to: support)
        }
        return
    }
    let payload = try decoder.decode(Payload.self, from: body)
    guard let request = BrowserRequest(url: payload.url, referrer: payload.referrer, filename: payload.filename,
                                       cookies: payload.cookies, userAgent: payload.userAgent) else { throw HostError.payload }
    let url = try BrowserRequest.url(for: request)
    if dryRun { return }
    // 旧版 App 即使收到 open 事件也不会建任务，先确认包内已注册下载协议。
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    guard let bundle = Bundle(url: app), bundle.bundleIdentifier == "com.yafaya.rainkeep",
          let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]],
          types.contains(where: { ($0["CFBundleURLSchemes"] as? [String])?.contains("rainkeep") == true })
    else { throw HostError.open }
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    do {
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config)
    } catch {
        // 系统错误可能包含原 URL，回复扩展时不带凭据。
        throw HostError.open
    }
}

/// stdout 只传输带小端长度前缀的 JSON。
private func writeReply(_ reply: Reply) throws {
    let body = try JSONEncoder().encode(reply)
    var length = UInt32(body.count).littleEndian
    var frame = withUnsafeBytes(of: &length) { Data($0) }
    frame.append(body)
    try FileHandle.standardOutput.write(contentsOf: frame)
}

do {
    try await handleMessage()
} catch {
    try writeReply(Reply(ok: false, error: error.localizedDescription))
    exit(0)
}
try writeReply(Reply(ok: true))
