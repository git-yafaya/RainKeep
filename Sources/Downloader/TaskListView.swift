// 任务列表与任务行：文件名 → 进度条 → 灰色小字，操作按钮悬停才出现
import DownloaderCore
import SwiftUI

struct TaskListView: View {
    @Environment(DownloadStore.self) private var store

    var body: some View {
        let items = store.visibleItems
        Group {
            if items.isEmpty {
                Text(store.items.isEmpty ? "把链接拖进来，或按 ⌘N" : "没有符合条件的任务")
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

private struct TaskRow: View {
    let item: DownloadItem
    @Environment(DownloadStore.self) private var store
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            FileIcon(name: item.name, color: item.category.color)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.name)
                if item.status != .completed {
                    ProgressLine(progress: item.progress, status: item.status)
                }
                Text(Format.summary(item))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(item.status == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) {
                let (icon, label) = toggleAction
                IconButton(systemName: icon, label: label) { store.toggle(item.id) }
                IconButton(systemName: "xmark", label: "移除") { store.remove(item.id) }
            }
            .opacity(hovering ? 1 : 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var toggleAction: (String, String) {
        switch item.status {
        case .downloading, .queued: ("pause.fill", "暂停")
        case .paused: ("play.fill", "继续")
        case .failed: ("arrow.clockwise", "重试")
        case .completed: ("folder", "在访达中显示")
        }
    }
}

private struct FileIcon: View {
    let name: String
    let color: Color

    var body: some View {
        let ext = (name as NSString).pathExtension.prefix(4).uppercased()
        Text(ext.isEmpty ? "—" : ext)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 36, height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.14)))
            .accessibilityHidden(true)
    }
}

private struct ProgressLine: View {
    let progress: Double
    let status: TaskStatus

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(fill).frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 3)
        .animation(.linear(duration: 0.5), value: progress)
    }

    private var fill: Color {
        switch status {
        case .downloading: .accentColor
        case .failed: .red
        default: .secondary.opacity(0.5)
        }
    }
}

/// 28pt 方形图标按钮：悬停灰底，键盘焦点中性细环
struct IconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 12, weight: .semibold))
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

    var body: some View {
        configuration.label
            .foregroundStyle(hovering ? .primary : .secondary)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering || configuration.isPressed ? Theme.hover : .clear))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.focusRing, lineWidth: isFocused ? 2 : 0))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
