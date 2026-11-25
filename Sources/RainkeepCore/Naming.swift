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

    /// 签名下载地址（GitHub、S3 用 response-content-disposition，Azure 用 rscd）把真名放在参数里，
    /// 路径最后一段只是一串 ID，所以先看参数
    private static let dispositionParams: Set<String> = ["response-content-disposition", "rscd"]

    public static func fileName(from url: URL) -> String {
        // 按表单规则解码：+ 是空格，%2B 才是加号（GitHub 的 rscd 就用 + 当空格）
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems ?? []
        let names = query.lazy
            .filter { dispositionParams.contains($0.name.lowercased()) }
            .compactMap { $0.value?.replacingOccurrences(of: "+", with: " ").removingPercentEncoding }
            .compactMap(fileName(fromDisposition:))
        if let name = names.first { return name }
        let last = url.lastPathComponent
        return last.isEmpty || last == "/" ? "download" : last
    }

    /// 解析 Content-Disposition 里的文件名，filename*（RFC 5987，可带中文）优先于 filename；只留最后一段，防止带目录
    static func fileName(fromDisposition disposition: String) -> String? {
        var plain: String?
        for part in disposition.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2 else { continue }
            let value = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            switch pair[0].lowercased() {
            case "filename*":
                // 形如 UTF-8''%E6%B5%8B.zip
                let encoded = value.components(separatedBy: "''").last ?? value
                if let name = safeName(encoded.removingPercentEncoding) { return name }
            case "filename":
                plain = safeName(value)
            default: continue
            }
        }
        return plain
    }

    private static func safeName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let name = (raw.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
        let invalid = name.isEmpty || name == "." || name == ".." || name.rangeOfCharacter(from: .controlCharacters) != nil
        return invalid ? nil : name
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
