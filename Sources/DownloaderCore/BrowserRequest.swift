// 在浏览器下载请求和 App 的 URL scheme 之间转换。
import Foundation

public struct BrowserRequest: Equatable, Sendable {
    public let url: URL
    public let referrer: String?
    public let filename: String?
    private let cookies: String?
    private let userAgent: String?

    public var headers: [String: String] {
        ["Cookie": cookies, "Referer": referrer, "User-Agent": userAgent].compactMapValues { $0 }
    }

    /// 校验下载链接、文件名和将进入 HTTP 请求头的值。
    public init?(url: URL, referrer: String? = nil, filename: String? = nil,
                 cookies: String? = nil, userAgent: String? = nil) {
        guard Naming.isWebURL(url), url.host?.isEmpty == false,
              [referrer, cookies, userAgent, filename].compactMap({ $0 }).allSatisfy({
                  $0.rangeOfCharacter(from: .controlCharacters) == nil
              }) else { return nil }
        if let filename, filename.isEmpty || filename == "." || filename == ".." || filename.contains("/") {
            return nil
        }
        self.url = url
        self.referrer = referrer
        self.filename = filename
        self.cookies = cookies
        self.userAgent = userAgent
    }

    /// 将浏览器字段逐项编码，保留原下载链接的查询参数和片段。
    public static func url(for request: Self) -> URL {
        var parts = URLComponents()
        parts.scheme = "downloader"
        parts.host = "add"
        var items = [URLQueryItem(name: "url", value: request.url.absoluteString)]
        for (name, value) in [("referrer", request.referrer), ("filename", request.filename),
                              ("cookies", request.cookies), ("userAgent", request.userAgent)] {
            if let value { items.append(URLQueryItem(name: name, value: value)) }
        }
        parts.queryItems = items
        return parts.url!
    }

    /// 只接受指向 add 的下载命令，拒绝重复参数和无效链接。
    public static func parse(_ url: URL) -> Self? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "downloader", parts.host?.lowercased() == "add",
              parts.user == nil, parts.password == nil, parts.port == nil, parts.path.isEmpty,
              parts.fragment == nil else { return nil }
        var fields: [String: String] = [:]
        for item in parts.queryItems ?? [] {
            guard let value = item.value, fields.updateValue(value, forKey: item.name) == nil else { return nil }
        }
        guard let raw = fields["url"], let link = URL(string: raw) else { return nil }
        return Self(url: link, referrer: fields["referrer"], filename: fields["filename"],
                    cookies: fields["cookies"], userAgent: fields["userAgent"])
    }
}
