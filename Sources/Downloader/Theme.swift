// 颜色、动效等设计 token，数值对应 docs/UI.md 和 prototype/index.html
import AppKit
import DownloaderCore
import SwiftUI

enum Theme {
    static let hover = adaptive(light: (0, 0.05), dark: (1, 0.06))
    static let selected = adaptive(light: (0, 0.07), dark: (1, 0.09))
    static let track = adaptive(light: (0, 0.07), dark: (1, 0.09))
    static let line = adaptive(light: (0, 0.07), dark: (1, 0.07))
    static let tree = adaptive(light: (0, 0.16), dark: (1, 0.16))
    static let segmentBackground = adaptive(light: (0, 0.05), dark: (1, 0.06))
    static let segmentThumb = adaptive(light: (1, 1), dark: (0.23, 1))
    static let menu = adaptive(light: (1, 1), dark: (0.17, 1))
    static let card = adaptive(light: (1, 1), dark: (0.14, 1))
    static let field = adaptive(light: (0, 0.03), dark: (1, 0.05))
    static let fieldFocus = adaptive(light: (0, 0.2), dark: (1, 0.2))
    static let focusRing = adaptive(light: (0, 0.22), dark: (1, 0.22))
    static let window = Color(nsColor: .windowBackgroundColor)

    /// (灰度, 透明度)，浅色 / 深色各一套
    private static func adaptive(light: (CGFloat, CGFloat), dark: (CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let (white, alpha) = isDark ? dark : light
            return NSColor(white: white, alpha: alpha)
        })
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
