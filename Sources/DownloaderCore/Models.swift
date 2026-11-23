// 下载任务的数据模型：文件分类、任务状态、任务本身，不依赖界面
import Foundation

public enum FileCategory: String, CaseIterable, Identifiable, Sendable {
    case video, audio, image, document, archive, installer, other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .video: "视频"
        case .audio: "音频"
        case .image: "图片"
        case .document: "文档"
        case .archive: "压缩包"
        case .installer: "安装包"
        case .other: "其他"
        }
    }

    private var extensions: Set<String> {
        switch self {
        case .video: ["mp4", "mkv", "mov", "avi", "webm", "m4v"]
        case .audio: ["mp3", "flac", "wav", "m4a", "aac", "ogg"]
        case .image: ["jpg", "jpeg", "png", "gif", "webp", "heic", "svg"]
        case .document: ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "epub", "pages", "key", "numbers"]
        case .archive: ["zip", "rar", "7z", "tar", "gz", "bz2", "xz"]
        case .installer: ["dmg", "pkg", "ipa"]
        case .other: []
        }
    }

    /// 按扩展名判断分类；.tar.gz 取最后一段 gz，同样归压缩包
    public static func of(fileName: String) -> FileCategory {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return allCases.first { $0.extensions.contains(ext) } ?? .other
    }
}

public enum TaskStatus: String, Codable, Sendable {
    case downloading, queued, paused, failed, completed
}

public struct DownloadItem: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var url: URL?
    public var size: Int64
    public var received: Int64
    public var status: TaskStatus
    /// 当前速度，字节/秒
    public var speed: Double = 0
    /// 最终文件路径，添加时按当时的下载位置和分类定下
    public var destination: URL?
    /// 失败原因或重试提示，显示在灰色小字里
    public var message: String?

    public init(id: UUID = UUID(), name: String, url: URL? = nil, destination: URL? = nil,
                size: Int64, received: Int64 = 0, status: TaskStatus = .queued) {
        self.id = id
        self.name = name
        self.url = url
        self.destination = destination
        self.size = size
        self.received = received
        self.status = status
    }

    public var category: FileCategory { .of(fileName: name) }

    public var progress: Double { size > 0 ? Double(received) / Double(size) : 0 }
}
