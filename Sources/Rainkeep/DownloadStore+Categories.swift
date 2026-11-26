// 自定义分类：新建、改名、删除、手动归类，以及按习惯自动归类和挪文件
import AppKit
import RainkeepCore

extension DownloadStore {
    func level(of selection: SidebarSelection) -> Int {
        switch selection {
        case .all: 1
        case .type: 2
        case .group(let id): categories.depth(of: id)
        }
    }

    func newCategory(parent: UUID?) {
        guard let category = categories.add(language.pick("未命名分类", "Untitled Category"), parent: parent) else { return }
        renaming = category.id
        justCreated = category.id
        save()
    }

    /// 名字为空保持原名；含 / 或 : 这类不能当文件夹名的字符时也保持原名，并说明原因
    func rename(_ id: UUID, to name: String) {
        let blank = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !categories.rename(id, to: name), !blank {
            showToast(language.pick("分类名不能包含 / 或 :", "Category name cannot contain / or :"), long: true)
        }
        renaming = nil
        justCreated = nil
        save()
    }

    /// 改名时按 Esc：刚新建还没起名的分类直接撤回，已有的分类保持原名
    func cancelRename(_ id: UUID) {
        if justCreated == id { categories.remove(id) }
        renaming = nil
        justCreated = nil
        save()
    }

    /// 删分类连同子分类，里面的任务保留、只是不再归类，文件留在原地
    func deleteCategory(_ id: UUID) {
        guard let name = categories[id]?.name else { return }
        let removed = categories.remove(id)
        learner.forget(removed)
        for i in items.indices where items[i].group.map(removed.contains) == true { items[i].group = nil }
        if case .group(let selected) = selection, removed.contains(selected) { selection = .all }
        save()
        showToast(language.pick("已删除分类「\(name)」，其中任务已保留", "Deleted “\(name)” (tasks kept)"))
    }

    /// 手动归类：给新分类加票，自动归错的给原分类扣票；已下完的文件立刻挪进分类文件夹，没下完的等下完再挪
    func assign(_ id: UUID, to group: UUID?) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].group != group else { return }
        if settings.learn {
            let features = items[i].features
                ?? LearnFeatures.make(url: items[i].url, referrer: nil, fileName: items[i].name)
            if items[i].autoSorted == true, let wrong = items[i].group { learner.retract(features, from: wrong) }
            if let group { learner.record(features, to: group) }
        }
        items[i].group = group
        items[i].autoSorted = nil
        if let group, let name = categories[group]?.name {
            relocate(id)
            showToast(language.pick("已移到「\(name)」", "Moved to “\(name)”"))
        }
        save()
    }

    /// 下完按文件内容再判断一次；用户手动归过类的不动。返回改了的分类
    func resort(_ id: UUID) -> CategoryLearner.Suggestion? {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].group == nil || items[i].autoSorted == true, let file = items[i].destination else { return nil }
        let content: [String]
        do {
            content = try ContentFingerprint.features(of: file)
        } catch {
            // 内容读不出来（比如 JSON 写坏了）只是少了内容特征，照链接特征的结果走，不打扰用户
            content = []
        }
        guard !content.isEmpty else { return nil }
        let features = (items[i].features ?? LearnFeatures.make(url: items[i].url, referrer: nil, fileName: items[i].name))
            + content
        items[i].features = features
        guard let suggestion = learner.suggest(features, in: categories),
              suggestion.category != items[i].group else { return nil }
        items[i].group = suggestion.category
        items[i].autoSorted = true
        return suggestion
    }

    /// 「已按习惯归入『世界书』· 文件内容相似」：说明是按哪条习惯分的
    func sortedMessage(_ suggestion: CategoryLearner.Suggestion) -> String {
        let name = categories[suggestion.category]?.name ?? ""
        let kind = suggestion.reason.prefix { $0 != ":" }
        let value = suggestion.reason.drop { $0 != ":" }.dropFirst()
        let reason = switch kind {
        case "json", "png": language.pick("文件内容相似", "similar content")
        case "ext": language.pick(".\(value) 文件", ".\(value) files")
        case "word": language.pick("文件名含「\(value)」", "name contains “\(value)”")
        default: language.pick("来自 \(value.prefix { $0 != "/" })", "from \(value.prefix { $0 != "/" })")
        }
        return language.pick("已按习惯归入「\(name)」· \(reason)", "Auto-sorted into “\(name)” · \(reason)")
    }

    /// 已完成且归了分类的文件挪到分类对应的文件夹，重名自动加序号
    func relocate(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].status == .completed,
              items[i].group != nil, let source = items[i].destination else { return }
        let dir = directory(for: items[i])
        guard source.deletingLastPathComponent().standardizedFileURL != dir.standardizedFileURL else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let name = Naming.uniqueName(source.lastPathComponent, taken: takenNames(in: dir))
            let target = dir.appending(path: name)
            try FileManager.default.moveItem(at: source, to: target)
            items[i].destination = target
            items[i].name = name
        } catch {
            showToast(language.pick("移动文件失败：", "Couldn't move the file: ") + error.localizedDescription)
        }
    }
}
