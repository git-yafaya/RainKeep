import Foundation

public enum ContentFingerprint {
    public static func features(of file: URL) throws -> [String] {
        let ext = file.pathExtension.lowercased()
        guard ext == "json" || ext == "png" else { return [] }
        let handle = try FileHandle(forReadingFrom: file)
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        if ext == "png" { return try png(handle, size: size) }

        let limit = 5 * 1024 * 1024
        guard size <= limit else { return [] }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { return [] }
        let json = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        guard let object = json as? [String: Any] else { return [] }
        return Set(object.keys.map { $0.lowercased() }).sorted().prefix(30).map { "json:" + $0 }
    }

    private static func png(_ handle: FileHandle, size: UInt64) throws -> [String] {
        guard size >= 8, try handle.read(upToCount: 8) == Data([137, 80, 78, 71, 13, 10, 26, 10]) else { return [] }
        var offset: UInt64 = 8
        var keys: Set<String> = []
        while size - offset >= 12 {
            guard let header = try handle.read(upToCount: 8), header.count == 8 else { break }
            let length = header.prefix(4).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            guard length <= 0x7fff_ffff, length <= size - offset - 12 else { break }
            let type = String(decoding: header.suffix(4), as: UTF8.self)
            if type == "IEND" { break }
            // 关键字最长 79 字节；跳过正文和 CRC，继续查找 IDAT 后面的文本块。
            if ["tEXt", "iTXt", "zTXt"].contains(type), length > 0,
               let prefix = try handle.read(upToCount: Int(min(length, 80))),
               let end = prefix.firstIndex(of: 0), end > prefix.startIndex,
               let key = String(data: prefix[..<end], encoding: .isoLatin1) {
                keys.insert("png:" + key.lowercased())
            }
            offset += 12 + length
            try handle.seek(toOffset: offset)
        }
        return keys.sorted()
    }
}
