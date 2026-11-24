// 自定义分类树（最多三级，顶级和「全部」并列）和分类习惯学习
import Foundation

public struct UserCategory: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    /// nil 表示顶级
    public var parent: UUID?
}

public struct CategoryTree: Codable, Sendable, Equatable {
    public static let maxDepth = 3
    public private(set) var items: [UserCategory] = []

    public init() {}

    public subscript(id: UUID) -> UserCategory? { items.first { $0.id == id } }

    public func children(of parent: UUID?) -> [UserCategory] { items.filter { $0.parent == parent } }

    /// 从顶级到自己，也是落盘的文件夹路径
    public func path(of id: UUID) -> [UserCategory] {
        var result: [UserCategory] = []
        var current = self[id]
        while let category = current {
            result.insert(category, at: 0)
            current = category.parent.flatMap { self[$0] }
        }
        return result
    }

    /// 顶级是 1
    public func depth(of id: UUID) -> Int { path(of: id).count }

    /// 自己加所有子孙，选中上级时显示整棵子树的任务
    public func subtree(of id: UUID) -> Set<UUID> {
        children(of: id).reduce(into: [id]) { $0.formUnion(subtree(of: $1.id)) }
    }

    public func canAddChild(to parent: UUID?) -> Bool {
        guard let parent else { return true }
        return self[parent] != nil && depth(of: parent) < Self.maxDepth
    }

    @discardableResult
    public mutating func add(_ name: String, parent: UUID?) -> UserCategory? {
        guard canAddChild(to: parent), let name = Self.validName(name) else { return nil }
        let category = UserCategory(id: UUID(), name: name, parent: parent)
        items.append(category)
        return category
    }

    /// 名字不合法（空、含 / 或 :、是 . 或 ..）时保持原名，返回 false
    @discardableResult
    public mutating func rename(_ id: UUID, to name: String) -> Bool {
        guard let i = items.firstIndex(where: { $0.id == id }), let name = Self.validName(name) else { return false }
        items[i].name = name
        return true
    }

    /// 连同子孙一起删，返回被删的 id，调用方据此把任务移出分类
    @discardableResult
    public mutating func remove(_ id: UUID) -> Set<UUID> {
        let removed = self[id] == nil ? [] : subtree(of: id)
        items.removeAll { removed.contains($0.id) }
        return removed
    }

    /// 分类名会当文件夹名用，所以拒绝路径分隔符
    static func validName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":") else { return nil }
        return name
    }
}

public enum LearnFeatures {
    fileprivate static func host(_ raw: String) -> String {
        let host = raw.lowercased()
        for prefix in ["www.", "cdn.", "dl.", "download."] where host.hasPrefix(prefix) {
            return String(host.dropFirst(prefix.count))
        }
        return host
    }

    public static func make(url: URL?, referrer: URL?, fileName: String, content: [String] = []) -> [String] {
        var keys: [String] = []
        let page = referrer?.host().map(host)
        if let page, !page.isEmpty { keys.append("page:" + page) }
        if let url, let site = url.host().map(host), !site.isEmpty {
            let directories = url.path(percentEncoded: true).split(separator: "/").dropLast()
            if directories.count >= 3 {
                keys.append("path:" + site + "/" + directories.prefix(2).joined(separator: "/").lowercased())
            }
            if site != page { keys.append("site:" + site) }
        }
        let name = (fileName as NSString).lastPathComponent.lowercased() as NSString
        if !name.pathExtension.isEmpty { keys.append("ext:" + name.pathExtension) }

        var words: [String] = []
        let runs = #/([\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}ー]+)|[\p{Latin}\p{Nd}]+/#
        for match in name.deletingPathExtension.matches(of: runs) {
            let run = match.output.0
            guard run.count >= 2 else { continue }
            if match.output.1 != nil {
                for (first, second) in zip(run, run.dropFirst()) {
                    let word = String([first, second])
                    if !words.contains(word) { words.append(word) }
                    if words.count == 12 { break }
                }
            } else if !run.allSatisfy(\.isNumber), !words.contains(String(run)) {
                words.append(String(run))
            }
            if words.count == 12 { break }
        }
        keys += words.map { "word:" + $0 }
        let fingerprints = Set(content.map { $0.lowercased() })
        keys += fingerprints.filter { $0.hasPrefix("json:") }.sorted().prefix(30)
        keys += fingerprints.filter { $0.hasPrefix("png:") }.sorted()
        return keys
    }
}

public struct CategoryLearner: Codable, Sendable, Equatable {
    public struct Suggestion: Sendable, Equatable {
        public let category: UUID
        public let reason: String
    }

    private struct Vote: Codable, Sendable, Equatable {
        let count: Double
        let updated: Date

        func value(at now: Date) -> Double {
            count * pow(0.5, max(0, now.timeIntervalSince(updated)) / (60 * 86_400))
        }
    }

    private var votes: [String: [UUID: Vote]] = [:]
    private static let weights: [String: Double] = [
        "page": 3, "path": 2, "site": 1, "ext": 2, "word": 2, "json": 4, "png": 4
    ]

    public init() {}

    /// 特征按具体程度分层，越具体越先判断；网站、扩展名这类各分类共有的特征会把票摊薄，
    /// 混在一起算时内容特征再明确也过不了门槛（同一 Discord 频道下的世界书、预设都是 .json）
    private static let tiers: [Set<String>] = [["json", "png"], ["path", "page", "word"], ["site", "ext"]]

    /// 从最具体的一层开始，第一层有把握的结果就用；都没把握返回 nil
    public func suggest(_ features: [String], in tree: CategoryTree, now: Date = .now) -> Suggestion? {
        for tier in Self.tiers {
            let keys = features.filter { tier.contains(String($0.prefix { $0 != ":" })) }
            if let suggestion = vote(keys, in: tree, now: now) { return suggestion }
        }
        return nil
    }

    /// 一层内加权投票：赢家占总分 ≥70%，且至少有一个特征给它 ≥2.5 票
    private func vote(_ features: [String], in tree: CategoryTree, now: Date) -> Suggestion? {
        let groups = Dictionary(grouping: Set(features).sorted()) { $0.prefix { $0 != ":" } }
        let categories = Set(tree.items.map(\.id))
        var scores: [UUID: Double] = [:]
        var reasons: [UUID: (key: String, contribution: Double)] = [:]
        var qualified: Set<UUID> = []
        for group in groups.keys.sorted() {
            guard let keys = groups[group], let weight = Self.weights[String(group)] else { continue }
            let share = weight / Double(keys.count)
            for key in keys {
                guard let bucket = votes[key] else { continue }
                for (category, vote) in bucket where categories.contains(category) {
                    let count = vote.value(at: now)
                    let contribution = share * count
                    scores[category, default: 0] += contribution
                    if count >= 2.5 { qualified.insert(category) }
                    if contribution > (reasons[category]?.contribution ?? 0) {
                        reasons[category] = (key, contribution)
                    }
                }
            }
        }
        guard let winner = scores.max(by: { $0.value < $1.value }),
              qualified.contains(winner.key), winner.value >= 0.7 * scores.values.reduce(0, +),
              let reason = reasons[winner.key] else { return nil }
        return Suggestion(category: winner.key, reason: reason.key)
    }

    public mutating func record(_ features: [String], to category: UUID, now: Date = .now) {
        update(features, category: category, delta: 1, now: now)
    }

    public mutating func retract(_ features: [String], from category: UUID, now: Date = .now) {
        update(features, category: category, delta: -1, now: now)
    }

    private mutating func update(_ features: [String], category: UUID, delta: Double, now: Date) {
        for key in Set(features) {
            var bucket = votes[key] ?? [:]
            let count = (bucket[category]?.value(at: now) ?? 0) + delta
            bucket[category] = count > 0 ? Vote(count: count, updated: now) : nil
            votes[key] = bucket.isEmpty ? nil : Self.limited(bucket, at: now)
        }
        trim(at: now)
    }

    private static func limited(_ bucket: [UUID: Vote], at now: Date) -> [UUID: Vote] {
        guard bucket.count > 8 else { return bucket }
        let strongest = bucket.sorted {
            ($0.value.value(at: now), $0.key) > ($1.value.value(at: now), $1.key)
        }.prefix(8)
        return Dictionary(uniqueKeysWithValues: strongest.map { ($0.key, $0.value) })
    }

    private mutating func trim(at now: Date) {
        guard votes.count > 512 else { return }
        let totals = votes.mapValues { $0.values.reduce(0) { $0 + $1.value(at: now) } }
        for entry in totals.sorted(by: { ($0.value, $0.key) < ($1.value, $1.key) }).prefix(votes.count - 512) {
            votes.removeValue(forKey: entry.key)
        }
    }

    public mutating func forget(_ categories: Set<UUID>) {
        votes = votes.compactMapValues { bucket in
            let kept = bucket.filter { !categories.contains($0.key) }
            return kept.isEmpty ? nil : kept
        }
    }

    private enum CodingKeys: CodingKey { case votes, habits }

    public init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        let now = Date.now
        if data.contains(.votes) {
            votes = try data.decode([String: [UUID: Vote]].self, forKey: .votes)
                .mapValues { Self.limited($0, at: now) }
            trim(at: now)
            return
        }
        struct Habit: Decodable { let category: UUID; let count: Int }
        let habits = try data.decode([String: Habit].self, forKey: .habits)
        for (old, habit) in habits where habit.count > 0 {
            let key: String
            if old.hasPrefix("host:") {
                key = "site:" + LearnFeatures.host(String(old.dropFirst(5)))
            } else if old.hasPrefix("ext:") {
                key = old.lowercased()
            } else { continue }
            let count = (votes[key]?[habit.category]?.count ?? 0) + Double(habit.count)
            votes[key, default: [:]][habit.category] = Vote(count: count, updated: now)
        }
        votes = votes.mapValues { Self.limited($0, at: now) }
        trim(at: now)
    }

    public func encode(to encoder: Encoder) throws {
        var data = encoder.container(keyedBy: CodingKeys.self)
        try data.encode(votes, forKey: .votes)
    }

}
