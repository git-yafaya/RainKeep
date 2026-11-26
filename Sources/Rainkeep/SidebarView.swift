// 侧栏：「全部」+ 类型二级；自定义分类和「全部」并列，最多三级；竖线 + 圆角折钩表达层级
// 同级切换滑块，跨级淡入淡出；分类可右键新建/改名/删除，任务行拖上来就归类
import AppKit
import RainkeepCore
import SwiftUI

struct SidebarView: View {
    @Environment(DownloadStore.self) private var store
    @Environment(\.language) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                    SidebarRow(title: language.pick("全部", "All"), count: store.count(for: .all), level: 1,
                               isSelected: store.selection == .all, namespace: namespace) { select(.all) }
                    TreeChildren(count: FileCategory.allCases.count) { index in
                        let type = FileCategory.allCases[index]
                        SidebarRow(title: type.name(language), count: store.count(for: .type(type)), level: 2,
                                   isSelected: store.selection == .type(type), namespace: namespace) {
                            select(.type(type))
                        }
                    }
                    ForEach(store.categories.children(of: nil)) { category in
                        CategoryNode(category: category, level: 1, namespace: namespace, select: select)
                            .padding(.top, 10)
                    }
                }
            }
            .contextMenu {
                Button(language.pick("新建分类", "New Category")) { store.newCategory(parent: nil) }
            }

            Spacer(minLength: 8)

            SidebarRow(title: language.pick("新建分类", "New Category"), systemImage: "folder.badge.plus", level: 1,
                       isSelected: false, namespace: namespace) { store.newCategory(parent: nil) }
            SidebarRow(title: language.pick("设置", "Settings"), systemImage: "slider.horizontal.3", level: 1,
                       isSelected: false, namespace: namespace) { store.present(.settings) }
                .help(language.pick("设置（⌘,）", "Settings (⌘,)"))
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .padding(.top, Layout.sidebarTop)
    }

    /// 同级用同一个匹配 id 让背景滑过去；跨级 id 不同，背景走淡入淡出
    private func select(_ selection: SidebarSelection) {
        guard selection != store.selection else { return }
        let crossLevel = store.level(of: selection) != store.level(of: store.selection)
        withAnimation(reduceMotion ? nil : (crossLevel ? Motion.fade : Motion.slide)) {
            store.selection = selection
        }
    }
}

/// 一组子项：每项左边挂折钩，最后一项的竖线不往下延伸；子项自己有子树时竖线贯穿整棵子树
private struct TreeChildren<Child: View>: View {
    let count: Int
    @ViewBuilder let child: (Int) -> Child
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                // 折钩挂在背景上：Shape 会占满可用高度，放进 HStack 会把行撑高
                child(index)
                    .padding(.vertical, 0.5)
                    .padding(.leading, 14)
                    .background(alignment: .leading) {
                        TreeConnector(isLast: index == count - 1)
                            .stroke(theme.tree, lineWidth: 1)
                            .frame(width: 14)
                    }
            }
        }
        .padding(.leading, 18)
    }
}

/// 自定义分类一行加它的子分类；SwiftUI 不支持不透明类型递归，子树用 AnyView 包一层
private struct CategoryNode: View {
    let category: UserCategory
    let level: Int
    let namespace: Namespace.ID
    let select: (SidebarSelection) -> Void
    @Environment(DownloadStore.self) private var store
    @Environment(\.language) private var language
    @State private var isDropTarget = false

    var body: some View {
        let children = store.categories.children(of: category.id)
        VStack(alignment: .leading, spacing: 1) {
            row
            if !children.isEmpty {
                TreeChildren(count: children.count) { index in
                    AnyView(CategoryNode(category: children[index], level: level + 1, namespace: namespace,
                                         select: select))
                }
            }
        }
    }

    @ViewBuilder private var row: some View {
        if store.renaming == category.id {
            RenameField(category: category, level: level)
        } else {
            SidebarRow(title: category.name, count: store.count(for: .group(category.id)), level: level,
                       isSelected: store.selection == .group(category.id), isDropTarget: isDropTarget,
                       namespace: namespace) { select(.group(category.id)) }
                .dropDestination(for: URL.self) { urls, _ in
                    let ids = urls.compactMap(TaskDrag.id(from:))
                    for id in ids { store.assign(id, to: category.id) }
                    return !ids.isEmpty
                } isTargeted: { isDropTarget = $0 }
                .contextMenu {
                    if store.categories.canAddChild(to: category.id) {
                        Button(language.pick("新建子分类", "New Subcategory")) { store.newCategory(parent: category.id) }
                    }
                    Button(language.pick("重命名", "Rename")) { store.renaming = category.id }
                    Divider()
                    Button(language.pick("删除分类", "Delete Category"), role: .destructive) {
                        store.deleteCategory(category.id)
                    }
                }
        }
    }
}

/// 行内改名：回车或失焦保存，Esc 放弃；名字不合法时保持原名
private struct RenameField: View {
    let category: UserCategory
    let level: Int
    @Environment(DownloadStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.language) private var language
    @State private var name = ""
    @State private var clickMonitor: Any?
    @State private var frame = CGRect.zero
    @FocusState private var focused: Bool

    var body: some View {
        TextField(language.pick("分类名", "Category name"), text: $name)
            .textFieldStyle(.plain)
            .fontWeight(level == 1 ? .semibold : .regular)
            .focused($focused)
            .padding(.horizontal, 4)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(theme.card))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(theme.fieldFocus))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .padding(.horizontal, 6)
            .frame(height: 28)
            .onAppear {
                name = category.name
                // 输入框刚挂上窗口时 macOS 不接焦点，等下一轮再给
                DispatchQueue.main.async { focused = true }
                clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: saveOnOutsideClick)
            }
            .onDisappear {
                if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            }
            .onSubmit { store.rename(category.id, to: name) }
            .onExitCommand { store.renaming = nil }
            .onChange(of: focused) { _, isFocused in
                if !isFocused, store.renaming == category.id { store.rename(category.id, to: name) }
            }
    }

    /// macOS 点空白处不会让输入框失焦，所以直接看点击位置：点到输入框以外就保存，不管它有没有拿到焦点
    private func saveOnOutsideClick(_ event: NSEvent) -> NSEvent? {
        guard let view = event.window?.contentView, store.renaming == category.id else { return event }
        var point = view.convert(event.locationInWindow, from: nil)
        if !view.isFlipped { point.y = view.bounds.height - point.y }
        if !frame.contains(point) { store.rename(category.id, to: name) }
        return event
    }
}

private struct SidebarRow: View {
    let title: String
    var systemImage: String?
    var count = 0
    let level: Int
    let isSelected: Bool
    var isDropTarget = false
    let namespace: Namespace.ID
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage).font(theme.font(12)) }
                Text(title)
                    .fontWeight(level == 1 && systemImage == nil ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if count > 0 {
                    Text("\(count)").font(theme.font(12)).monospacedDigit().foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(level == 1 || isSelected ? .primary : .secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background {
                ZStack {
                    if isDropTarget {
                        RoundedRectangle(cornerRadius: 6).fill(theme.accent.opacity(0.18))
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 6).fill(theme.hover)
                    }
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.selected)
                            .matchedGeometryEffect(id: "selection-\(level)", in: namespace)
                            .transition(.opacity)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 竖线往下走到第一行中间，拐个圆角钩向右；不是最后一项时竖线继续往下，贯穿它的整棵子树
private struct TreeConnector: Shape {
    let isLast: Bool
    private let hookWidth: CGFloat = 10
    private let radius: CGFloat = 6
    /// 行高 28 + 上下各 0.5 间距的一半
    private let hookY: CGFloat = 14.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.minX + 0.5
        let mid = rect.minY + hookY
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: mid - radius))
        path.addQuadCurve(to: CGPoint(x: x + radius, y: mid), control: CGPoint(x: x, y: mid))
        path.addLine(to: CGPoint(x: rect.minX + hookWidth, y: mid))
        if !isLast {
            path.move(to: CGPoint(x: x, y: mid - radius))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        return path
    }
}
