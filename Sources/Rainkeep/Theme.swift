// 设计 token：配色（跟随系统 + 三套主题 + 背景图时自适应字色）、字号倍数、动效；数值对应 prototype/index.html
import AppKit
import RainkeepCore
import SwiftUI

struct Theme {
    /// nil 表示跟随系统深浅色
    var scheme: ColorScheme?
    var text = Color.primary
    var accent = Color.accentColor
    var onAccent = Color.white
    var danger = Color.red
    var sidebar = Color.clear
    var content = Color.clear
    var menu = Color.clear
    var card = Color.clear
    var segmentThumb = Color.clear
    var selected = Color.clear
    var hover = Color.clear
    var track = Color.clear
    var line = Color.clear
    var tree = Color.clear
    var segmentBackground = Color.clear
    var field = Color.clear
    var fieldFocus = Color.clear
    var focusRing = Color.clear
    var scale: CGFloat = 1

    /// 所有字号都走这里，跟着字号设置一起缩放
    func font(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size * scale, weight: weight, design: design)
    }

    /// backgroundIsBright 为 nil 表示没设背景图
    static func make(_ choice: ThemeChoice, textSize: Int, backgroundIsBright: Bool?) -> Theme {
        var theme = palette(choice)
        if let bright = backgroundIsBright { theme.adapt(toBrightImage: bright) }
        theme.scale = CGFloat(textSize) / CGFloat(TextSize.base)
        return theme
    }

    private static func palette(_ choice: ThemeChoice) -> Theme {
        switch choice {
        case .system: system
        // 树冠下的深绿
        case .rainforest:
            custom(scheme: .dark, ink: Color(hex: 0xE4F1E8), text: Color(hex: 0xE4F1E8),
                   accent: Color(hex: 0x3FCF8E), onAccent: Color(hex: 0x06281A), danger: Color(hex: 0xFF6B5B),
                   content: Color(hex: 0x11211A), sidebar: Color(hex: 0x0D1B14), menu: Color(hex: 0x182D22),
                   card: Color(hex: 0x163024), thumb: Color(hex: 0x23402F))
        // 暖奶油底，橙色点缀
        case .orange:
            custom(scheme: .light, ink: Color(hex: 0x784614), text: Color(hex: 0x3B2A1C),
                   accent: Color(hex: 0xF47321), onAccent: .white, danger: Color(hex: 0xD93A2B),
                   content: Color(hex: 0xFFFAF3), sidebar: Color(hex: 0xFBEFDF), menu: Color(hex: 0xFFFAF3),
                   card: Color(hex: 0xFBF0E2), thumb: .white)
        // 象牙白花瓣，湿润的灰绿叶
        case .gardenia:
            custom(scheme: .light, ink: Color(hex: 0x283C32), text: Color(hex: 0x26302B),
                   accent: Color(hex: 0x5E8C78), onAccent: .white, danger: Color(hex: 0xC9594D),
                   content: Color(hex: 0xFBFBF7), sidebar: Color(hex: 0xF0F3EE), menu: .white,
                   card: Color(hex: 0xF2F4EF), thumb: .white)
        }
    }

    private static let system = Theme(
        sidebar: adaptive(light: (0.961, 1), dark: (0.145, 1)),
        content: adaptive(light: (1, 1), dark: (0.118, 1)),
        menu: adaptive(light: (1, 1), dark: (0.17, 1)),
        card: adaptive(light: (1, 1), dark: (0.14, 1)),
        segmentThumb: adaptive(light: (1, 1), dark: (0.23, 1)),
        selected: adaptive(light: (0, 0.07), dark: (1, 0.09)),
        hover: adaptive(light: (0, 0.05), dark: (1, 0.06)),
        track: adaptive(light: (0, 0.07), dark: (1, 0.09)),
        line: adaptive(light: (0, 0.07), dark: (1, 0.07)),
        tree: adaptive(light: (0, 0.16), dark: (1, 0.16)),
        segmentBackground: adaptive(light: (0, 0.05), dark: (1, 0.06)),
        field: adaptive(light: (0, 0.03), dark: (1, 0.05)),
        fieldFocus: adaptive(light: (0, 0.2), dark: (1, 0.2)),
        focusRing: adaptive(light: (0, 0.22), dark: (1, 0.22)))

    /// 主题配色：线条、悬停这类半透明 token 都由同一个墨色按固定比例调出来
    private static func custom(scheme: ColorScheme, ink: Color, text: Color, accent: Color, onAccent: Color,
                               danger: Color, content: Color, sidebar: Color, menu: Color, card: Color,
                               thumb: Color) -> Theme {
        var theme = Theme(scheme: scheme, text: text, accent: accent, onAccent: onAccent, danger: danger,
                          sidebar: sidebar, content: content, menu: menu, card: card, segmentThumb: thumb,
                          selected: accent.opacity(0.15))
        theme.useInk(ink)
        return theme
    }

    private mutating func useInk(_ ink: Color) {
        hover = ink.opacity(0.06)
        track = ink.opacity(0.1)
        line = ink.opacity(0.08)
        tree = ink.opacity(0.18)
        segmentBackground = ink.opacity(0.07)
        field = ink.opacity(0.04)
        fieldFocus = ink.opacity(0.2)
        focusRing = ink.opacity(0.22)
    }

    /// 背景图：亮图配深色字 + 白色半透明蒙版，暗图配浅色字 + 黑色蒙版，保证字看得清；强调色仍用主题的
    private mutating func adapt(toBrightImage bright: Bool) {
        let veil: Color = bright ? .white : .black
        scheme = bright ? .light : .dark
        text = bright ? Color(white: 0.11) : Color(white: 0.96)
        useInk(bright ? .black : .white)
        selected = (bright ? Color.black : .white).opacity(bright ? 0.09 : 0.14)
        sidebar = veil.opacity(bright ? 0.78 : 0.58)
        content = veil.opacity(bright ? 0.66 : 0.46)
        menu = bright ? .white : Color(white: 0.17)
        card = bright ? .white : Color(white: 0.14)
        segmentThumb = bright ? .white : .white.opacity(0.2)
    }

    /// (灰度, 透明度)，浅色 / 深色各一套，跟随系统外观
    private static func adaptive(light: (CGFloat, CGFloat), dark: (CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let (white, alpha) = isDark ? dark : light
            return NSColor(white: white, alpha: alpha)
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension EnvironmentValues {
    @Entry var theme = Theme.make(.system, textSize: TextSize.base, backgroundIsBright: nil)
    @Entry var language = Language.zh
}

/// 主窗口和菜单栏面板共用：注入配色、语言和正文字号
struct Themed: ViewModifier {
    @Environment(DownloadStore.self) private var store

    func body(content: Content) -> some View {
        let theme = store.theme
        content
            .environment(\.theme, theme)
            .environment(\.language, store.language)
            .font(theme.font(13))
            .foregroundStyle(theme.text)
            // 不在这里加 .tint：自定义强调色会让 AppKit 每次刷新都生成新的外观对象、触发 KVO 再刷新，死循环
    }
}

enum Motion {
    /// 同级切换：选中背景滑过去
    static let slide = Animation.timingCurve(0.3, 0.7, 0.2, 1, duration: 0.28)
    /// 跨级切换：淡入淡出
    static let fade = Animation.easeOut(duration: 0.22)
    static let dialog = Animation.timingCurve(0.3, 0.7, 0.2, 1, duration: 0.2)
    static let menu = Animation.timingCurve(0.3, 0.7, 0.2, 1, duration: 0.14)
    static let rowEnter = Animation.timingCurve(0.3, 0.7, 0.2, 1, duration: 0.26)
    static let rowStagger = 0.022
    static let staggerCap = 12
}

extension FileCategory {
    var color: Color {
        switch self {
        case .video: .purple
        case .audio: .pink
        case .image: .orange
        case .document: .blue
        case .archive: .brown
        case .installer, .other: .gray
        }
    }
}
