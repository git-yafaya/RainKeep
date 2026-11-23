// 主窗口：自绘侧栏（可拖宽）+ 顶栏 + 任务列表，外加弹窗、提示和拖拽添加
// 不用系统分栏和工具栏：它们的浮动侧栏、按钮样式和动画都跟原型对不上
import AppKit
import DownloaderCore
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
    @State private var isDropTargeted = false
    @AppStorage("sidebarWidth") private var sidebarWidth = Layout.sidebarDefault

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: sidebarWidth)
                .background { Theme.sidebar.modifier(WindowDragArea()) }
                .overlay(alignment: .trailing) {
                    SidebarResizer(width: $sidebarWidth).offset(x: 4)
                }
                .zIndex(1)
            VStack(spacing: 0) {
                HeaderBar()
                TaskListView()
                StatusBar()
            }
            .background(Theme.content)
            .overlay(alignment: .leading) { Theme.line.frame(width: 1) }
        }
        .ignoresSafeArea()
        .overlay { DialogHost() }
        .overlay(alignment: .bottom) { ToastView() }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(6)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let web = urls.filter(Naming.isWebURL)
            if web.isEmpty { store.showToast("没有识别到链接") } else { store.add(urls: web) }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .focusEffectDisabled()
        .onAppear { store.start() }
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
    @State private var dragStart: Double?
    @State private var hovering = false

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .overlay {
                Color.accentColor
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
            .accessibilityLabel("调整侧栏宽度")
            .accessibilityValue("\(Int(width))")
    }
}

/// 顶栏：当前分类名 · 状态切换 · 全部暂停/继续 · 添加
private struct HeaderBar: View {
    @Environment(DownloadStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            Text(store.category?.displayName ?? "全部")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            StatusSegmented().padding(.trailing, 6)
            IconButton(systemName: store.isRunning ? "pause.fill" : "play.fill",
                       label: store.isRunning ? "全部暂停" : "全部继续") { store.pauseOrResumeAll() }
                .disabled(!store.isRunning && !store.hasPaused)
            IconButton(systemName: "plus", label: "添加下载（⌘N）", font: .system(size: 15, weight: .regular)) {
                store.present(.add)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .frame(height: Layout.headerHeight)
        .background { Color.clear.contentShape(Rectangle()).modifier(WindowDragArea()) }
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }
}

/// 全部 / 进行中 / 已完成，选中背景滑动
struct StatusSegmented: View {
    @Environment(DownloadStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(StatusFilter.allCases) { filter in
                let selected = store.statusFilter == filter
                Button {
                    withAnimation(reduceMotion ? nil : Motion.slide) { store.statusFilter = filter }
                } label: {
                    Text(filter.title)
                        .font(.system(size: 12))
                        .foregroundStyle(selected ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 22)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Theme.segmentThumb)
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
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.segmentBackground))
    }
}

struct StatusBar: View {
    @Environment(DownloadStore.self) private var store

    var body: some View {
        let active = store.activeItems
        HStack {
            Spacer()
            if !active.isEmpty {
                Text("\(active.count) 个下载中 · \(Format.bytes(active.reduce(0) { $0 + $1.speed }))/s")
            }
        }
        .font(.system(size: 11.5))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .frame(height: 32)
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }
}

struct ToastView: View {
    @Environment(DownloadStore.self) private var store

    var body: some View {
        ZStack {
            if let text = store.toastText {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.92)))
                    .transition(.opacity)
            }
        }
        .padding(.bottom, 44)
        .animation(.easeOut(duration: 0.2), value: store.toastText)
        .allowsHitTesting(false)
    }
}
