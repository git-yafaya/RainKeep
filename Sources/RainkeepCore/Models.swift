// 下载任务的数据模型：文件分类、任务状态、任务本身，不依赖界面
import Foundation

public enum FileCategory: String, CaseIterable, Identifiable, Sendable {
    case video, audio, image, document, archive, installer, other

    public var id: String { rawValue }

    /// 界面名，也是「按类型放进子文件夹」时的文件夹名
    public func name(_ language: Language) -> String {
        switch self {
        case .video: language.pick("视频", "Video")
        case .audio: language.pick("音频", "Audio")
        case .image: language.pick("图片", "Images")
        case .document: language.pick("文档", "Documents")
        case .archive: language.pick("压缩包", "Archives")
        case .installer: language.pick("安装包", "Installers")
        case .other: language.pick("其他", "Other")
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
    /// 用户自定义分类，nil 表示没归类
    public var group: UUID?
    /// 学习用的特征（链接、来源页、文件名，下完后加上文件内容）；老版本存的任务没有
    public var features: [String]?
    /// 分类是按习惯自动归的；用户挪走时要给原分类扣票。老版本存的任务没有，当作 false
    public var autoSorted: Bool?
    /// 名字是从链接猜的（浏览器没给），下完换成服务器给的名字。老版本存的任务没有，当作 false
    public var guessedName: Bool?

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
