// 界面语言：中文 / English，文案就地成对写，不建字典
import Foundation

public enum Language: String, Codable, Sendable, CaseIterable {
    case zh, en

    /// 系统首选语言是中文就用中文，其余一律英文
    public static var system: Language {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .zh : .en
    }

    public func pick(_ zh: String, _ en: String) -> String { self == .zh ? zh : en }
}
