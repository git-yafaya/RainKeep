// 链接解析与文件命名：从文本挑出网页链接、取文件名、重名加序号
import Foundation

public enum Naming {
    /// 只认 http/https 链接，其余片段丢掉
    public static func parseURLs(_ text: String) -> [URL] {
        text.split(whereSeparator: \.isWhitespace).compactMap { URL(string: String($0)) }.filter(isWebURL)
    }

    public static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), url.host != nil else { return false }
        return scheme == "http" || scheme == "https"
    }

    public static func fileName(from url: URL) -> String {
        let last = url.lastPathComponent
        return last.isEmpty || last == "/" ? "download" : last
    }

    /// 重名时加 " (1)"、" (2)"……
    public static func uniqueName(_ name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var n = 1
        while true {
            let candidate = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            if !taken.contains(candidate) { return candidate }
            n += 1
        }
    }
}
