// 存盘格式（state.json）：设置、任务列表、自定义分类和学到的习惯。1.0 起格式固定，只加可选字段
import Foundation

public enum ThemeChoice: String, Codable, CaseIterable, Sendable {
    case system, rainforest, orange, gardenia

    public func name(_ language: Language) -> String {
        switch self {
        case .system: language.pick("跟随系统", "System")
        case .rainforest: language.pick("热带雨林", "Rainforest")
        case .orange: language.pick("初夏橙皮", "Orange Peel")
        case .gardenia: language.pick("雨后栀子", "Gardenia")
        }
    }
}

/// 正文字号（px），其他字号按和 13px 的比例一起缩放
public enum TextSize {
    public static let options = [12, 13, 14, 15, 16]
    public static let base = 13
}

public struct AppSettings: Equatable, Codable, Sendable {
    public var downloadDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    public var maxActive = 3
    /// 每个任务分几段，0 表示自动
    public var threads = 0
    public var classify = true
    public var learn = true
    public var notify = true
    public var menuBar = true
    public var theme = ThemeChoice.system
    /// 正文字号 px
    public var textSize = TextSize.base
    /// nil 表示跟随系统
    public var language: Language?
    public var background: URL?

    public init() {}

    /// 老版本存的设置缺新字段，缺的用默认值
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        downloadDir = try c.decodeIfPresent(URL.self, forKey: .downloadDir) ?? d.downloadDir
        maxActive = try c.decodeIfPresent(Int.self, forKey: .maxActive) ?? d.maxActive
        threads = try c.decodeIfPresent(Int.self, forKey: .threads) ?? d.threads
        classify = try c.decodeIfPresent(Bool.self, forKey: .classify) ?? d.classify
        learn = try c.decodeIfPresent(Bool.self, forKey: .learn) ?? d.learn
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? d.notify
        menuBar = try c.decodeIfPresent(Bool.self, forKey: .menuBar) ?? d.menuBar
        theme = try c.decodeIfPresent(ThemeChoice.self, forKey: .theme) ?? d.theme
        // 老版本的 fontSize（小/标准/大）不迁移，回到默认 13px
        let size = try c.decodeIfPresent(Int.self, forKey: .textSize)
        textSize = size.flatMap { TextSize.options.contains($0) ? $0 : nil } ?? d.textSize
        language = try c.decodeIfPresent(Language.self, forKey: .language)
        background = try c.decodeIfPresent(URL.self, forKey: .background)
    }
}

/// 存盘内容；自定义分类和学到的习惯是后加的，老版本存盘里没有
public struct SavedState: Codable, Sendable {
    public var items: [DownloadItem]
    public var settings: AppSettings
    public var categories: CategoryTree?
    public var learner: CategoryLearner?

    public init(items: [DownloadItem], settings: AppSettings, categories: CategoryTree?, learner: CategoryLearner?) {
        self.items = items
        self.settings = settings
        self.categories = categories
        self.learner = learner
    }

    /// 读存盘并整理成启动时的样子：上次没下完的重新排队，速度清零，只留失败原因
    public static func restore(from data: Data) throws -> SavedState {
        var state = try JSONDecoder().decode(SavedState.self, from: data)
        state.items = state.items.map { item in
            var item = item
            if item.status == .downloading { item.status = .queued }
            item.speed = 0
            if item.status != .failed { item.message = nil }
            return item
        }
        return state
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func brokenBackupURL(for file: URL, at date: Date = .now) -> URL {
        file.deletingLastPathComponent().appending(path: "state.broken-\(Int64(date.timeIntervalSince1970)).json")
    }
}
