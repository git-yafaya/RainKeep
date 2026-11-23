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

/// 记下用户手动归类时的来源网站和扩展名；同一来源连续归到同一分类够次数后，新任务自动归进去
public struct CategoryLearner: Codable, Sendable, Equatable {
    public static let threshold = 3

    private struct Habit: Codable, Sendable, Equatable {
        var category: UUID
        var count: Int
    }

    private var habits: [String: Habit] = [:]

    public init() {}

    /// 来源网站排在扩展名前面，建议时网站优先
    static func keys(url: URL?, fileName: String) -> [String] {
        var keys: [String] = []
        if let host = url?.host()?.lowercased(), !host.isEmpty {
            keys.append("host:" + (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host))
        }
        let ext = (fileName as NSString).pathExtension.lowercased()
        if !ext.isEmpty { keys.append("ext:" + ext) }
        return keys
    }

    /// 归到同一分类计数加一，换了分类从 1 重新数
    public mutating func record(url: URL?, fileName: String, category: UUID) {
        for key in Self.keys(url: url, fileName: fileName) {
            let count = habits[key]?.category == category ? habits[key]!.count + 1 : 1
            habits[key] = Habit(category: category, count: count)
        }
    }

    /// 分类已被删掉的习惯不再用
    public func suggest(url: URL?, fileName: String, in tree: CategoryTree) -> UUID? {
        for key in Self.keys(url: url, fileName: fileName) {
            if let habit = habits[key], habit.count >= Self.threshold, tree[habit.category] != nil {
                return habit.category
            }
        }
        return nil
    }
}
