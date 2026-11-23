// 侧栏：「全部」一级，分类二级用竖线 + 圆角折钩挂在下面；同级切换滑块，跨级淡入淡出
import DownloaderCore
import SwiftUI

struct SidebarView: View {
    @Environment(DownloadStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            SidebarRow(title: "全部", count: store.count(for: nil), level: 1,
                       isSelected: store.category == nil, namespace: namespace) { select(nil) }

            VStack(spacing: 0) {
                let categories = FileCategory.allCases
                ForEach(categories) { category in
                    // 折钩挂在背景上：Shape 会占满可用高度，放进 HStack 会把行撑高
                    SidebarRow(title: category.displayName, count: store.count(for: category), level: 2,
                               isSelected: store.category == category, namespace: namespace) { select(category) }
                        .padding(.vertical, 0.5)
                        .padding(.leading, 14)
                        .background(alignment: .leading) {
                            TreeConnector(isLast: category == categories.last)
                                .stroke(Theme.tree, lineWidth: 1)
                                .frame(width: 14)
                        }
                }
            }
            .padding(.leading, 18)

            Spacer()

            SidebarRow(title: "设置", systemImage: "slider.horizontal.3", level: 1, isSelected: false,
                       namespace: namespace) { store.present(.settings) }
                .help("设置（⌘,）")
        }
        .padding(10)
    }

    /// 同级用同一个匹配 id 让背景滑过去；跨级 id 不同，背景走淡入淡出
    private func select(_ category: FileCategory?) {
        guard category != store.category else { return }
        let crossLevel = (category == nil) != (store.category == nil)
        withAnimation(reduceMotion ? nil : (crossLevel ? Motion.fade : Motion.slide)) {
            store.category = category
        }
    }
}

private struct SidebarRow: View {
    let title: String
    var systemImage: String?
    var count = 0
    let level: Int
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 12)) }
                Text(title)
                    .fontWeight(level == 1 && systemImage == nil ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if count > 0 {
                    Text("\(count)").font(.system(size: 12)).monospacedDigit().foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(level == 1 || isSelected ? .primary : .secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background {
                ZStack {
                    if hovering { RoundedRectangle(cornerRadius: 6).fill(Theme.hover) }
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.selected)
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

/// 一段竖线往下走到行中间，拐个圆角钩向右；不是最后一项时竖线继续往下
private struct TreeConnector: Shape {
    let isLast: Bool
    private let hookWidth: CGFloat = 10
    private let radius: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.minX + 0.5
        let mid = rect.midY
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
