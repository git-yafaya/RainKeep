// 居中弹窗：添加下载、设置；以及设置里用的自绘下拉
import AppKit
import DownloaderCore
import SwiftUI

struct DialogHost: View {
    @Environment(DownloadStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let dialog = store.dialog {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture { store.dismissDialog() }
                    .transition(.opacity)
                Group {
                    switch dialog {
                    case .add: AddDialog()
                    case .settings: SettingsDialog()
                    }
                }
                .padding(16)
                .frame(width: 460)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                .shadow(color: .black.opacity(0.18), radius: 30, y: 10)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(reduceMotion ? nil : Motion.dialog, value: store.dialog)
    }
}

private struct AddDialog: View {
    @Environment(DownloadStore.self) private var store
    @State private var text = ""
    @State private var error = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 120)
                .focused($focused)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Theme.fieldFocus : Theme.line))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("粘贴链接，每行一个")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 11)
                            .padding(.top, 6)
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: focused)
                .accessibilityLabel("下载链接")
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .frame(minHeight: 18, alignment: .topLeading)
                .padding(.top, 4)
            HStack(spacing: 8) {
                Spacer()
                Button("取消") { store.dismissDialog() }
                    .keyboardShortcut(.cancelAction)
                Button("下载") { confirm() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { focused = true }
    }

    private func confirm() {
        let urls = Naming.parseURLs(text)
        guard !urls.isEmpty else {
            error = "没有识别到 http/https 链接"
            return
        }
        store.dismissDialog()
        store.add(urls: urls)
    }
}

private enum SettingMenu {
    case maxActive, threads
}

private struct SettingsDialog: View {
    @Environment(DownloadStore.self) private var store
    @State private var openMenu: SettingMenu?

    private static let maxActiveOptions = [1, 2, 3, 4, 5, 6, 8].map { (value: $0, label: "\($0) 个") }
    private static let threadOptions = [(value: 0, label: "自动")] + [2, 4, 8, 16].map { (value: $0, label: "\($0) 段") }

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 0) {
            Text("设置").font(.system(size: 13, weight: .semibold)).padding(.bottom, 6)

            SettingRow(title: "下载位置") {
                Text(store.downloadDirDisplay)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Button("更改…", action: chooseFolder).controlSize(.small)
            }
            Theme.line.frame(height: 1)
            SettingRow(title: "同时下载") {
                Dropdown(options: Self.maxActiveOptions, selection: $store.settings.maxActive,
                         isOpen: binding(for: .maxActive), label: "同时下载")
            }
            .zIndex(openMenu == .maxActive ? 1 : 0)
            Theme.line.frame(height: 1)
            SettingRow(title: "每个任务分段") {
                Dropdown(options: Self.threadOptions, selection: $store.settings.threads,
                         isOpen: binding(for: .threads), label: "每个任务分段")
            }
            .zIndex(openMenu == .threads ? 1 : 0)
            Theme.line.frame(height: 1)
            SettingRow(title: "按类型放进子文件夹") {
                Toggle("按类型放进子文件夹", isOn: $store.settings.classify).toggleStyle(.switch).labelsHidden()
            }
            Theme.line.frame(height: 1)
            SettingRow(title: "完成后通知") {
                Toggle("完成后通知", isOn: $store.settings.notify).toggleStyle(.switch).labelsHidden()
            }

            HStack {
                Spacer()
                // Esc 先收下拉，再关弹窗
                Button("完成") {
                    if openMenu != nil { openMenu = nil } else { store.dismissDialog() }
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 14)
        }
        .contentShape(Rectangle())
        .onTapGesture { openMenu = nil }
    }

    private func binding(for menu: SettingMenu) -> Binding<Bool> {
        Binding(
            get: { openMenu == menu },
            set: { open in
                withAnimation(Motion.menu) { openMenu = open ? menu : nil }
            }
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = store.settings.downloadDir
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.downloadDir = url
        }
    }
}

private struct SettingRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            HStack(spacing: 8) { content }
        }
        .frame(minHeight: 42)
    }
}

/// 自绘下拉：按钮下方展开、跟主题变色，Esc 和点外面能收起（由外层控制 isOpen）
private struct Dropdown<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Binding var isOpen: Bool
    let label: String

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 10) {
                Text(options.first { $0.value == selection }?.label ?? "")
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .font(.system(size: 12))
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(minWidth: 84, minHeight: 24, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.segmentBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(options.first { $0.value == selection }?.label ?? "")
        .overlay(alignment: .topTrailing) {
            if isOpen {
                menu
                    .offset(y: 28)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(options, id: \.value) { option in
                DropdownOption(label: option.label, isSelected: option.value == selection) {
                    selection = option.value
                    isOpen = false
                }
            }
        }
        .padding(4)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.menu))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
    }
}

private struct DropdownOption: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(isSelected ? 1 : 0)
                Text(label)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .foregroundStyle(hovering ? Color.white : Color.primary)
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .frame(minWidth: 84, minHeight: 24)
            .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Color.accentColor : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
