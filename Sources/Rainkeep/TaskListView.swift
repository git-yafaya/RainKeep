// 任务列表与任务行：文件名 → 进度条 → 灰色小字，操作按钮悬停才出现；行可拖到侧栏分类，右键可移到分类
import RainkeepCore
import SwiftUI

/// 任务行拖拽时带的内容：用私有 scheme 的 URL，侧栏认得出，主窗口的拖链接添加会忽略它
enum TaskDrag {
    static let scheme = "rainkeep-task"

    static func url(for id: UUID) -> URL { URL(string: "\(scheme):\(id.uuidString)")! }

    static func id(from url: URL) -> UUID? {
        guard url.scheme == scheme else { return nil }
        return UUID(uuidString: String(url.absoluteString.dropFirst(scheme.count + 1)))
    }
}

struct TaskListView: View {
    @Environment(DownloadStore.self) private var store
    @Environment(\.language) private var language

    var body: some View {
        let items = store.visibleItems
        Group {
            if items.isEmpty {
                Text(store.items.isEmpty ? language.pick("把链接拖进来，或按 ⌘N", "Drop links here, or press ⌘N")
                                         : language.pick("没有符合条件的任务", "No matching tasks"))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(EnterAnimation(index: 0))
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            TaskRow(item: item).modifier(EnterAnimation(index: index))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
        }
        .id(store.filterKey)        // 筛选变了整块重建，触发逐行入场
        // 只在筛选变化这一下去掉动画：旧列表立刻换掉，不跟着侧栏动画淡出；行入场动画在之后的 onAppear 里，不受影响
        .transaction(value: store.filterKey) { $0.animation = nil }
    }
}

/// 逐行淡入上移；进度刷新不会重建行，所以不会重播
private struct EnterAnimation: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .onAppear {
                guard !reduceMotion else { shown = true; return }
                let delay = Double(min(index, Motion.staggerCap)) * Motion.rowStagger
                withAnimation(Motion.rowEnter.delay(delay)) { shown = true }
            }
    }
}

struct TaskRow: View {
    let item: DownloadItem
    /// 菜单栏面板里的紧凑版：图标小一号，只留主按钮，常显
    var compact = false
    @Environment(DownloadStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.language) private var language
    @State private var hovering = false

    var body: some View {
        HStack(spacing: compact ? 10 : 12) {
            FileIcon(name: item.name, color: item.category.color, side: compact ? 28 : 36)
            VStack(alignment: .leading, spacing: compact ? 4 : 5) {
                Text(item.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.name)
                if item.status != .completed {
                    ProgressLine(progress: item.progress, status: item.status)
                }
                Text(Format.summary(item, language, groupName: store.groupName(of: item)))
                    .font(theme.font(11.5))
                    .monospacedDigit()
                    .foregroundStyle(item.status == .failed ? AnyShapeStyle(theme.danger) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) {
                let (icon, label) = toggleAction
                IconButton(systemName: icon, label: label) { store.toggle(item.id) }
                if !compact {
                    IconButton(systemName: "xmark", label: language.pick("移除", "Remove")) { store.remove(item.id) }
                }
            }
            .opacity(hovering || compact ? 1 : 0)
        }
        .padding(compact ? 8 : 10)
        .background(RoundedRectangle(cornerRadius: compact ? 10 : 8).fill(hovering ? theme.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .draggable(TaskDrag.url(for: item.id)) {
            Text(item.name).padding(6).background(RoundedRectangle(cornerRadius: 6).fill(theme.card))
        }
        .contextMenu { if !compact { menu } }
    }

    /// 右键：移到某个分类（按层级缩进）、移出分类、移除任务
    @ViewBuilder private var menu: some View {
        let categories = flattened(parent: nil, depth: 0)
        if !categories.isEmpty {
            Menu(language.pick("移到分类", "Move to")) {
                ForEach(categories, id: \.category.id) { entry in
                    Button(String(repeating: "    ", count: entry.depth) + entry.category.name) {
                        store.assign(item.id, to: entry.category.id)
                    }
                }
                if item.group != nil {
                    Divider()
                    Button(language.pick("不放进分类", "No Category")) { store.assign(item.id, to: nil) }
                }
            }
            Divider()
        }
        Button(language.pick("移除", "Remove"), role: .destructive) { store.remove(item.id) }
    }

    private func flattened(parent: UUID?, depth: Int) -> [(category: UserCategory, depth: Int)] {
        store.categories.children(of: parent).flatMap { [($0, depth)] + flattened(parent: $0.id, depth: depth + 1) }
    }

    private var toggleAction: (String, String) {
        switch item.status {
        case .downloading, .queued: ("pause.fill", language.pick("暂停", "Pause"))
        case .paused: ("play.fill", language.pick("继续", "Resume"))
        case .failed: ("arrow.clockwise", language.pick("重试", "Retry"))
        case .completed: ("folder", language.pick("在访达中显示", "Show in Finder"))
        }
    }
}

private struct FileIcon: View {
    let name: String
    let color: Color
    let side: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        let ext = (name as NSString).pathExtension.prefix(4).uppercased()
        Text(ext.isEmpty ? "—" : ext)
            .font(theme.font(side * 0.26, .bold))
            .foregroundStyle(color)
            .frame(width: side, height: side)
            .background(RoundedRectangle(cornerRadius: side * 0.22).fill(color.opacity(0.14)))
            .accessibilityHidden(true)
    }
}

private struct ProgressLine: View {
    let progress: Double
    let status: TaskStatus
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.track)
                Capsule().fill(fill).frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 3)
        .animation(.linear(duration: 0.5), value: progress)
    }

    private var fill: Color {
        switch status {
        case .downloading: theme.accent
        case .failed: theme.danger
        default: theme.text.opacity(0.3)
        }
    }
}

/// 28pt 方形图标按钮：悬停灰底，键盘焦点中性细环
struct IconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 12
    var weight = Font.Weight.semibold
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName).font(theme.font(size, weight))
        }
        .buttonStyle(IconButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.theme) private var theme

    var body: some View {
        configuration.label
            .foregroundStyle(hovering && isEnabled ? .primary : .secondary)
            .opacity(isEnabled ? 1 : 0.35)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(isEnabled && (hovering || configuration.isPressed) ? theme.hover : .clear))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.focusRing, lineWidth: isFocused ? 2 : 0))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
