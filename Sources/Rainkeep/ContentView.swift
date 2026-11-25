// 主窗口：自绘侧栏（可拖宽）+ 顶栏 + 任务列表，外加背景图、弹窗、提示和拖拽添加
// 不用系统分栏和工具栏：它们的浮动侧栏、按钮样式和动画都跟原型对不上
import AppKit
import RainkeepCore
import SwiftUI

enum Layout {
    static let sidebarMin = 160.0
    static let sidebarMax = 340.0
    static let sidebarDefault = 210.0
    static let sidebarStep = 10.0
    static let headerHeight = 52.0
    /// 侧栏顶部给红绿灯留的空间
    static let sidebarTop = 44.0

    static func clampSidebar(_ width: Double) -> Double {
        min(sidebarMax, max(sidebarMin, width.rounded()))
    }
}

struct ContentView: View {
    @Environment(DownloadStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.language) private var language
    @State private var isDropTargeted = false
    @AppStorage("sidebarWidth") private var sidebarWidth = Layout.sidebarDefault

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: sidebarWidth)
                .background { theme.sidebar.modifier(WindowDragArea()) }
                .overlay(alignment: .trailing) {
                    SidebarResizer(width: $sidebarWidth).offset(x: 4)
                }
                .zIndex(1)
            VStack(spacing: 0) {
                HeaderBar()
                TaskListView()
                StatusBar()
            }
            .background(theme.content)
            .overlay(alignment: .leading) { theme.line.frame(width: 1) }
        }
        .background { BackgroundImage() }
        .ignoresSafeArea()
        .overlay { DialogHost() }
        .overlay(alignment: .bottom) { ToastView() }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(theme.accent, lineWidth: 2)
                    .padding(6)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            // 任务行拖到侧栏以外的地方松手时也会落到这里，不当成链接
            guard !urls.contains(where: { $0.scheme == TaskDrag.scheme }) else { return false }
            let web = urls.filter(Naming.isWebURL)
            if web.isEmpty {
                store.showToast(language.pick("没有识别到链接", "No links found"))
            } else {
                store.add(urls: web)
            }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .focusEffectDisabled()
    }
}

/// 用户自选的背景图铺满窗口；侧栏和主区各盖一层半透明蒙版（见 Theme.adapt）
private struct BackgroundImage: View {
    @Environment(DownloadStore.self) private var store

    var body: some View {
        if let image = store.backgroundImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .accessibilityHidden(true)
        }
    }
}

/// 隐藏标题栏后，用空白处拖动窗口
private struct WindowDragArea: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.gesture(WindowDragGesture())
        } else {
            content
        }
    }
}

/// 侧栏右边缘的拖动条：鼠标拖或 ←/→ 键调宽度，范围 160–340
private struct SidebarResizer: View {
    @Binding var width: Double
    @Environment(\.theme) private var theme
    @Environment(\.language) private var language
    @State private var dragStart: Double?
    @State private var hovering = false

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .overlay {
                theme.accent
                    .opacity(hovering || dragStart != nil ? 0.5 : 0)
                    .frame(width: 2)
                    .animation(.easeOut(duration: 0.15), value: hovering)
            }
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? width
                        dragStart = start
                        width = Layout.clampSidebar(start + value.translation.width)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .focusable()
            .onKeyPress(.leftArrow) {
                width = Layout.clampSidebar(width - Layout.sidebarStep)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                width = Layout.clampSidebar(width + Layout.sidebarStep)
                return .handled
            }
            .accessibilityLabel(language.pick("调整侧栏宽度", "Resize sidebar"))
            .accessibilityValue("\(Int(width))")
    }
}

/// 顶栏：当前分类名 · 状态切换 · 更新天气 · 全部暂停/继续 · 添加
private struct HeaderBar: View {
    @Environment(DownloadStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.language) private var language

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 8) {
            Text(store.title)
                .font(theme.font(15, .semibold))
                .lineLimit(1)
            Spacer()
            Segmented(options: StatusFilter.allCases.map { ($0, $0.title(language)) },
                      selection: $store.statusFilter)
                .padding(.trailing, 6)
            Button(action: store.checkOrCatchUpdate) { UpdateSky(phase: store.update) }
                .buttonStyle(IconButtonStyle())
                .help(updateTip)
                .accessibilityLabel(updateTip)
            IconButton(systemName: store.isRunning ? "pause.fill" : "play.fill",
                       label: store.isRunning ? language.pick("全部暂停", "Pause All")
                                              : language.pick("全部继续", "Resume All")) { store.pauseOrResumeAll() }
                .disabled(!store.isRunning && !store.hasPaused)
            IconButton(systemName: "plus", label: language.pick("添加下载（⌘N）", "Add Download (⌘N)"), size: 15,
                       weight: .regular) {
                store.present(.add)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .frame(height: Layout.headerHeight)
        .background { Color.clear.contentShape(Rectangle()).modifier(WindowDragArea()) }
        .overlay(alignment: .bottom) { theme.line.frame(height: 1) }
    }

    private var updateTip: String {
        switch store.update {
        case .idle: language.pick("检查更新", "Check for Updates")
        case .available(let release): language.pick("新雨已至 · \(release.version)，点击接住", "Fresh rain is here · \(release.version). Click to catch it")
        default: store.update.status(language)
        }
    }
}

/// 分段控件（顶栏的全部 / 进行中 / 已完成、设置页签），选中背景滑动
struct Segmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = selection == option.value
                Button {
                    withAnimation(reduceMotion ? nil : Motion.slide) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(theme.font(12))
                        .foregroundStyle(selected ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 22)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(theme.segmentThumb)
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(theme.segmentBackground))
    }
}

struct StatusBar: View {
    @Environment(DownloadStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.language) private var language

    var body: some View {
        let count = store.activeItems.count
        HStack {
            Spacer()
            if count > 0 {
                Text(language.pick("\(count) 个下载中", "\(count) downloading") + " · \(Format.bytes(store.totalSpeed))/s")
            }
        }
        .font(theme.font(11.5))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .frame(height: 32)
        .overlay(alignment: .top) { theme.line.frame(height: 1) }
    }
}

struct ToastView: View {
    @Environment(DownloadStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            if let item = store.items.first(where: { $0.id == store.pendingDelete }) {
                // 点了删除后紧接着出完成提示，确认条直接消失，免得两条叠着淡入淡出
                DeleteConfirm(item: item).transition(.asymmetric(insertion: .opacity, removal: .identity))
            } else if let text = store.toastText {
                Text(text)
                    .font(theme.font(12))
                    .foregroundStyle(theme.card)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.text.opacity(0.92)))
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 44)
        .animation(.easeOut(duration: 0.2), value: store.toastText)
        .animation(.easeOut(duration: 0.2), value: store.pendingDelete)
    }
}

/// 删除确认条：和提示同一位置，等用户点取消或删除，Esc 取消；文件名太长时截掉中间
private struct DeleteConfirm: View {
    let item: DownloadItem
    @Environment(DownloadStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.language) private var language
    private static let nameWidth: CGFloat = 260

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                Text(language.pick("删除「", "Delete “")).layoutPriority(1)
                Text(item.name).lineLimit(1).truncationMode(.middle).frame(maxWidth: Self.nameWidth)
                Text(consequence).layoutPriority(1)
            }
            .padding(.trailing, 6)
            Button(language.pick("取消", "Cancel")) { store.pendingDelete = nil }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(ToastButtonStyle(color: theme.card.opacity(0.75)))
            Button(language.pick("删除", "Delete")) { store.confirmDelete() }
                .fontWeight(.semibold)
                .buttonStyle(ToastButtonStyle(color: theme.danger))
        }
        .font(theme.font(12))
        .foregroundStyle(theme.card)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.text.opacity(0.92)))
        .accessibilityElement(children: .contain)
    }

    private var consequence: String {
        item.status == .completed
            ? language.pick("」？文件会移到废纸篓", "”? The file will be moved to the Trash.")
            : language.pick("」？已下载的部分会一起删除", "”? Downloaded data will be discarded.")
    }
}

/// 确认条里的文字按钮：悬停时垫一层浅底
private struct ToastButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        ToastButtonBody(configuration: configuration, color: color)
    }
}

private struct ToastButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let color: Color
    @State private var hovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        configuration.label
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(theme.card.opacity(hovering ? 0.18 : 0)))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
