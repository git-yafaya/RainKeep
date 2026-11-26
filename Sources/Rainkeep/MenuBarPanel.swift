// 菜单栏小图标和下拉面板（仿 Vorssaint）：顶部水滴图标、页签、小标题、圆角卡片、底部两个按钮
import AppKit
import RainkeepCore
import SwiftUI

/// 应用图标里的线稿水滴，做成模板图跟随菜单栏深浅
enum DropIcon {
    private static let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="230 240 564 610" width="16" height="16" fill="none" \
    stroke="black" stroke-width="64" stroke-linecap="round" stroke-linejoin="round">\
    <path d="M512 290 C462 368 382 460 382 568 a130 130 0 0 0 260 0 C642 460 562 368 512 290 Z"/>\
    <path d="M262 750 A250 46 0 0 0 762 750"/></svg>
    """

    static func image(side: CGFloat) -> NSImage {
        let image = NSImage(data: Data(svg.utf8)) ?? NSImage()
        image.size = NSSize(width: side, height: side)
        image.isTemplate = true
        return image
    }
}

/// 菜单栏上的图标；有下载时后面跟总速度，有失败任务时水滴旁带一个危险色圆点
struct MenuBarLabel: View {
    @Environment(DownloadStore.self) private var store
    private static let icon = DropIcon.image(side: 15)

    var body: some View {
        let speed = store.activeItems.isEmpty ? "" : " \(Format.bytes(store.totalSpeed))/s"
        if store.items.contains(where: { $0.status == .failed }) {
            // 菜单栏只认文字和图片，圆点画成非模板图，才能保留颜色
            Text("\(Image(nsImage: Self.icon))\(Image(nsImage: Self.dot(store.theme.danger)))\(speed)").monospacedDigit()
        } else if speed.isEmpty {
            Image(nsImage: Self.icon)
        } else {
            Text("\(Image(nsImage: Self.icon))\(speed)").monospacedDigit()
        }
    }

    private static func dot(_ color: Color) -> NSImage {
        let side = 6.0
        let image = NSImage(size: NSSize(width: side + 2, height: side), flipped: false) { _ in
            NSColor(color).setFill()
            NSBezierPath(ovalIn: NSRect(x: 2, y: 0, width: side, height: side)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

private enum PanelTab {
    case active, done
}

struct MenuBarPanel: View {
    private static let limit = 6
    private static let logo = DropIcon.image(side: 44)

    @Environment(DownloadStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.language) private var language
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace
    @State private var tab = PanelTab.active

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: Self.logo)
                .renderingMode(.template)
                .padding(.bottom, 2)
                .accessibilityHidden(true)
            tabs
            Text(title)
                .font(theme.font(12, .semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
            card
            HStack(spacing: 8) {
                FooterButton(systemName: "macwindow", title: language.pick("打开拾雨", "Open Rainkeep")) {
                    openWindow(id: RainkeepApp.mainWindow)
                    NSApp.activate()
                }
                FooterButton(systemName: "power", title: language.pick("退出", "Quit")) {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(EdgeInsets(top: 18, leading: 14, bottom: 14, trailing: 14))
        .frame(width: 320)
        .background(theme.card)
    }

    /// 「进行中」和主窗口口径一致：所有未完成任务，失败的置顶方便重试，其余最新在前
    private func items(_ tab: PanelTab) -> [DownloadItem] {
        let list: [DownloadItem] = switch tab {
        case .active:
            store.items.filter { $0.status == .failed }.reversed()
                + store.items.filter { $0.status != .completed && $0.status != .failed }.reversed()
        case .done:
            store.items.filter { $0.status == .completed }.reversed()
        }
        return Array(list.prefix(Self.limit))
    }

    /// 进行中 · N 个下载中 · 速度 · N 个失败；没在下载时才提已暂停数
    private var title: String {
        guard tab == .active else { return language.pick("最近完成", "Recently Completed") }
        let downloading = store.activeItems.count
        let failed = store.items.filter { $0.status == .failed }.count
        let paused = store.items.filter { $0.status == .paused }.count
        var parts = [language.pick("进行中", "Active")]
        if downloading > 0 {
            parts.append(language.pick("\(downloading) 个下载中", "\(downloading) downloading") + " · \(Format.bytes(store.totalSpeed))/s")
        }
        if failed > 0 {
            parts.append(language.pick("\(failed) 个失败", "\(failed) failed"))
        } else if downloading == 0, paused > 0 {
            parts.append(language.pick("\(paused) 个已暂停", "\(paused) paused"))
        }
        return parts.joined(separator: " · ")
    }

    /// 两个图标页签，选中背景滑过去
    private var tabs: some View {
        HStack(spacing: 0) {
            tabButton(.active, systemName: "arrow.down", label: language.pick("进行中", "Active"))
            tabButton(.done, systemName: "checkmark", label: language.pick("最近完成", "Recently Completed"))
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.field))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.line))
    }

    private func tabButton(_ value: PanelTab, systemName: String, label: String) -> some View {
        let selected = tab == value
        return Button {
            withAnimation(reduceMotion ? nil : Motion.slide) { tab = value }
        } label: {
            Image(systemName: systemName)
                .font(theme.font(14, .semibold))
                .foregroundStyle(selected ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity, minHeight: 34)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(theme.accent.opacity(0.14))
                            .matchedGeometryEffect(id: "tab", in: namespace)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 两页叠在一起只显示当前页，卡片取两页中较高的那个，切页签时面板不跳
    private var card: some View {
        ZStack(alignment: .top) {
            page(.active)
            page(.done)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.field))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.line))
    }

    private func page(_ value: PanelTab) -> some View {
        let list = items(value)
        let shown = tab == value
        return VStack(spacing: 2) {
            if list.isEmpty {
                Text(value == .active ? language.pick("没有进行中的下载", "Nothing downloading")
                                      : language.pick("还没有完成的下载", "Nothing finished yet"))
                    .font(theme.font(12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 64)
            } else {
                ForEach(list) { TaskRow(item: $0, compact: true) }
            }
        }
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
    }
}

/// 底部等宽描边按钮
private struct FooterButton: View {
    let systemName: String
    let title: String
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(theme.font(12))
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? theme.hover : .clear))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.line))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
