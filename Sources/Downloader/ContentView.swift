// 主窗口：侧栏 + 任务列表 + 工具栏，外加弹窗、提示和拖拽添加
import DownloaderCore
import SwiftUI

struct ContentView: View {
    @Environment(DownloadStore.self) private var store
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 160, ideal: 210, max: 340)
        } detail: {
            TaskListView()
                .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
                .navigationTitle(store.category?.displayName ?? "全部")
                .toolbar { toolbarContent }
        }
        .overlay { DialogHost() }
        .overlay(alignment: .bottom) { ToastView() }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let web = urls.filter(Naming.isWebURL)
            if web.isEmpty { store.showToast("没有识别到链接") } else { store.add(urls: web) }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .focusEffectDisabled()
        .onAppear { store.startSimulation() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            StatusSegmented()
            Button {
                store.pauseOrResumeAll()
            } label: {
                Label(store.isRunning ? "全部暂停" : "全部继续", systemImage: store.isRunning ? "pause.fill" : "play.fill")
            }
            .help(store.isRunning ? "全部暂停" : "全部继续")
            .disabled(!store.isRunning && !store.hasPaused)
            Button {
                store.present(.add)
            } label: {
                Label("添加下载", systemImage: "plus")
            }
            .help("添加下载（⌘N）")
        }
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
        .background(Theme.window)
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
                    .foregroundStyle(Theme.window)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.92)))
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(.bottom, 44)
        .animation(.easeOut(duration: 0.2), value: store.toastText)
        .allowsHitTesting(false)
    }
}
