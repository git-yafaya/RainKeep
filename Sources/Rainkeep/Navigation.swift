// 界面导航状态：侧栏选中项、状态筛选、打开的弹窗
import Foundation
import RainkeepCore

enum StatusFilter: CaseIterable, Identifiable {
    case all, active, done
    var id: Self { self }
    func title(_ language: Language) -> String {
        switch self {
        case .all: language.pick("全部", "All")
        case .active: language.pick("进行中", "Active")
        case .done: language.pick("已完成", "Completed")
        }
    }
}

/// 侧栏选中项：全部、某个类型、某个自定义分类
enum SidebarSelection: Hashable {
    case all
    case type(FileCategory)
    case group(UUID)
}

enum Dialog: Equatable {
    case add, settings
}
