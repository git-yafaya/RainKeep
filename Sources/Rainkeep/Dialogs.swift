// 居中弹窗：添加下载、设置；以及设置里用的自绘下拉
import AppKit
import UniformTypeIdentifiers
import RainkeepCore
import SwiftUI

struct DialogHost: View {
    @Environment(DownloadStore.self) private var store
    @Environment(\.theme) private var theme
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
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.card))
                .shadow(color: .black.opacity(0.18), radius: 30, y: 10)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(reduceMotion ? nil : Motion.dialog, value: store.dialog)
    }
}

private struct AddDialog: View {
    @Environment(DownloadStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.language) private var language
    @State private var text = ""
    @State private var error = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $text)
                .font(theme.font(12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6)
                .padding(.vertical, 12)
                .frame(height: 120)
                .focused($focused)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.field))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? theme.fieldFocus : theme.line))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(language.pick("粘贴链接，每行一个", "Paste links, one per line"))
                            .font(theme.font(12))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 11)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: focused)
                .accessibilityLabel(language.pick("下载链接", "Download links"))
            Text(error)
                .font(theme.font(12))
                .foregroundStyle(theme.danger)
                .frame(minHeight: 18, alignment: .topLeading)
                .padding(.top, 4)
            HStack(spacing: 8) {
                Spacer()
                Button(language.pick("取消", "Cancel")) { store.dismissDialog() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(DialogButtonStyle())
                Button(language.pick("下载", "Download")) { confirm() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(DialogButtonStyle(isPrimary: true))
            }
        }
        .onAppear { focused = true }
    }

    private func confirm() {
        let urls = Naming.parseURLs(text)
        guard !urls.isEmpty else {
            error = language.pick("没有识别到 http/https 链接", "No http/https links found")
            return
        }
        store.dismissDialog()
        store.add(urls: urls)
    }
}

private enum SettingMenu {
    case maxActive, threads, theme, fontSize, language
}

private enum SettingsPage {
    case general, appearance
}

/// 设置分「常规 / 外观」两页，页签是滑块分段控件
private struct SettingsDialog: View {
    @Environment(DownloadStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.language) private var language
    @State private var page = SettingsPage.general
    @State private var openMenu: SettingMenu?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.pick("设置", "Settings")).font(theme.font(13, .semibold))
                Spacer()
                Segmented(options: [(SettingsPage.general, language.pick("常规", "General")),
                                    (.appearance, language.pick("外观", "Appearance"))],
                          selection: $page)
            }
            .padding(.bottom, 6)

            // 页签滑块有动画，页面内容直接换，免得两页叠着淡变还溢出卡片
            Group {
                switch page {
                case .general: general
                case .appearance: appearance
                }
            }
            .transaction(value: page) { $0.animation = nil }

            HStack {
                Spacer()
                // Esc 先收下拉，再关弹窗
                Button(language.pick("完成", "Done")) {
                    if openMenu != nil { openMenu = nil } else { store.dismissDialog() }
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(DialogButtonStyle(isPrimary: true))
            }
            .padding(.top, 14)
        }
        .contentShape(Rectangle())
        .onTapGesture { openMenu = nil }
    }

    @ViewBuilder private var general: some View {
        @Bindable var store = store
        SettingRow(title: language.pick("下载位置", "Save to")) {
            Text(store.downloadDirDisplay)
                .font(theme.font(12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Button(language.pick("更改…", "Change…"), action: chooseFolder).buttonStyle(DialogButtonStyle(isSmall: true))
        }
        divider
        dropdownRow(.maxActive, language.pick("同时下载", "Simultaneous"), selection: $store.settings.maxActive,
                    options: [1, 2, 3, 4, 5, 6, 8].map { ($0, language.pick("\($0) 个", "\($0)")) })
        divider
        dropdownRow(.threads, language.pick("每个任务分段", "Segments per task"), selection: $store.settings.threads,
                    options: [(0, language.pick("自动", "Auto"))] + [2, 4, 8, 16].map { ($0, language.pick("\($0) 段", "\($0)")) })
        divider
        toggleRow(language.pick("按类型放进子文件夹", "Sort into folders by type"), isOn: $store.settings.classify)
        divider
        toggleRow(language.pick("学习我的分类习惯", "Learn my sorting habits"), isOn: $store.settings.learn)
        divider
        toggleRow(language.pick("完成后通知", "Notify when done"), isOn: $store.settings.notify)
        divider
        toggleRow(language.pick("在菜单栏显示", "Show in menu bar"), isOn: $store.settings.menuBar)
        divider
        SettingRow(title: language.pick("接管浏览器下载", "Take over browser downloads")) {
            if let link = store.browserLink {
                let browser = link.browser ?? language.pick("浏览器", "browser")
                Text(language.pick("已连接 \(browser)", "Connected to \(browser)"))
                    .font(theme.font(12))
                    .foregroundStyle(.secondary)
            } else {
                Text(language.pick("未连接", "Not connected"))
                    .font(theme.font(12))
                    .foregroundStyle(.secondary)
                Button(language.pick("接管", "Connect"), action: store.connectBrowser)
                    .buttonStyle(DialogButtonStyle(isSmall: true))
            }
        }
        // 用户把扩展拖进浏览器后，扩展会连一次宿主留下记录；设置开着时隔两秒看一眼
        .task {
            while !Task.isCancelled {
                store.refreshBrowserLink()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    @ViewBuilder private var appearance: some View {
        @Bindable var store = store
        dropdownRow(.theme, language.pick("主题", "Theme"), selection: $store.settings.theme,
                    options: ThemeChoice.allCases.map { ($0, $0.name(language)) })
        divider
        dropdownRow(.fontSize, language.pick("字号", "Text size"), selection: $store.settings.textSize,
                    options: TextSize.options.map { ($0, "\($0) px") })
        divider
        SettingRow(title: language.pick("背景图片", "Background image")) {
            if store.settings.background != nil {
                Button(language.pick("移除", "Remove")) { store.settings.background = nil }
                    .buttonStyle(DialogButtonStyle(isSmall: true))
            }
            Button(language.pick("选择…", "Choose…"), action: chooseBackground).buttonStyle(DialogButtonStyle(isSmall: true))
        }
        divider
        dropdownRow(.language, language.pick("语言", "Language"), selection: $store.settings.language,
                    options: [(nil, language.pick("跟随系统", "System")), (.zh, "中文"), (.en, "English")])
    }

    private var divider: some View { theme.line.frame(height: 1) }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        SettingRow(title: title) {
            Toggle(title, isOn: isOn).toggleStyle(SwitchStyle()).labelsHidden()
        }
    }

    /// 打开的下拉要盖住下面的行，所以把这一行提到上层
    private func dropdownRow<Value: Hashable>(_ menu: SettingMenu, _ title: String, selection: Binding<Value>,
                                              options: [(value: Value, label: String)]) -> some View {
        SettingRow(title: title) {
            Dropdown(options: options, selection: selection, isOpen: binding(for: menu), label: title)
        }
        .zIndex(openMenu == menu ? 1 : 0)
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

    private func chooseBackground() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.background = url
        }
    }
}

/// 弹窗按钮：扁平圆角，普通灰底、主按钮强调色；small 用在设置行里（不用系统按钮，样式对不上原型）
private struct DialogButtonStyle: ButtonStyle {
    var isPrimary = false
    var isSmall = false

    func makeBody(configuration: Configuration) -> some View {
        DialogButtonBody(configuration: configuration, isPrimary: isPrimary, isSmall: isSmall)
    }
}

private struct DialogButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isPrimary: Bool
    let isSmall: Bool
    @Environment(\.isFocused) private var isFocused
    @Environment(\.theme) private var theme

    var body: some View {
        configuration.label
            .font(theme.font(isSmall ? 12 : 13))
            .foregroundStyle(isPrimary ? theme.onAccent : theme.text)
            .padding(.horizontal, isSmall ? 10 : 14)
            .frame(height: isSmall ? 22 : 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(isPrimary ? theme.accent : theme.segmentBackground))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.focusRing, lineWidth: isFocused ? 2 : 0))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

/// 自绘开关 32×19：打开是主题强调色，滑钮带动画
private struct SwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SwitchBody(configuration: configuration)
    }
}

private struct SwitchBody: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.theme) private var theme
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .timingCurve(0.3, 0.7, 0.2, 1, duration: 0.2)) {
                configuration.isOn.toggle()
            }
        } label: {
            Capsule()
                .fill(configuration.isOn ? theme.accent : theme.segmentBackground.opacity(2.4))
                .frame(width: 32, height: 19)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                        .frame(width: 15, height: 15)
                        .padding(2)
                }
                .overlay(Capsule().stroke(theme.focusRing, lineWidth: isFocused ? 2 : 0))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
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

/// 自绘下拉：按钮下方展开、和按钮等宽、文字左边对齐，跟主题变色；Esc 和点外面能收起（由外层控制 isOpen）
private struct Dropdown<Value: Hashable>: View {
    /// 放得下英文选项（如 Orange Peel）
    static var width: CGFloat { 120 }
    /// 按钮文字左内边距；菜单内边距 4 + 选项左内边距 6 也等于它，两边文字才能对齐
    static var textInset: CGFloat { 10 }

    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Binding var isOpen: Bool
    let label: String
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 0) {
                Text(options.first { $0.value == selection }?.label ?? "")
                Spacer(minLength: 6)
                Image(systemName: "chevron.down")
                    .font(theme.font(9, .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .font(theme.font(12))
            .padding(.leading, Self.textInset)
            .padding(.trailing, 8)
            .frame(width: Self.width, height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(theme.segmentBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(options.first { $0.value == selection }?.label ?? "")
        .overlay(alignment: .topLeading) {
            if isOpen {
                menu
                    .offset(y: 28)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
    }

    private var menu: some View {
        VStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                DropdownOption(label: option.label, isSelected: option.value == selection,
                               leadingInset: Self.textInset - 4) {
                    selection = option.value
                    isOpen = false
                }
            }
        }
        .padding(4)
        .frame(width: Self.width)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.menu))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.line))
    }
}

private struct DropdownOption: View {
    let label: String
    let isSelected: Bool
    let leadingInset: CGFloat
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(label)
                Spacer(minLength: 6)
                Image(systemName: "checkmark")
                    .font(theme.font(10, .semibold))
                    .opacity(isSelected ? 1 : 0)
            }
            .font(theme.font(12))
            .foregroundStyle(hovering ? theme.onAccent : theme.text)
            .padding(.leading, leadingInset)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? theme.accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
