// 检查更新：读 GitHub 最新正式版，比较版本号，找出安装包下载地址
import Foundation

public struct Release: Sendable, Equatable {
    /// 去掉开头 v 的版本号，如 1.1
    public let version: String
    /// 发布页，没有安装包时打开它
    public let page: URL
    /// .dmg 安装包，拾雨自己就能下
    public let installer: URL?
}

public enum UpdateCheck {
    public static let latestURL = URL(string: "https://api.github.com/repos/git-yafaya/RainKeep/releases/latest")!

    public static func latest(session: URLSession = .shared) async throws -> Release {
        var request = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EngineError.invalidResponse }
        guard http.statusCode == 200 else { throw EngineError.status(http.statusCode) }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> Release {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Payload: Decodable { let tag_name: String; let html_url: URL; let assets: [Asset] }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        let installer = payload.assets.first { $0.name.lowercased().hasSuffix(".dmg") }?.browser_download_url
        return Release(version: version, page: payload.html_url, installer: installer)
    }

    /// 按数字逐段比，1.10 比 1.9 新，1.0 和 1.0.0 一样
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = numbers(candidate), b = numbers(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func numbers(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}
