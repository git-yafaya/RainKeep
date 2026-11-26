// 更新检测：启动时查一次 GitHub 最新版；设置行和顶栏的天气图标共用这份状态
import AppKit
import RainkeepCore
import SwiftUI

enum UpdatePhase: Equatable {
    case idle, checking, latest, failed(String)
    case available(Release)
    /// 安装包正在下载，跟着这个任务的进度走
    case catching(Release, UUID)
    /// 安装包下好了，点一下就打开
    case ready(Release, URL)

    static let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    private static func percent(_ progress: Double) -> Int { min(99, Int((progress * 100).rounded())) }

    /// progress 只在接雨时用，显示到 99% 为止，下完直接换成「新雨已落」
    func status(_ language: Language, progress: Double = 0) -> String {
        switch self {
        case .idle: language.pick("当前 \(Self.current)", "Version \(Self.current)")
        case .checking: language.pick("正在望云…", "Watching the clouds…")
        case .latest: language.pick("天晴 · 已是最新", "Clear skies · Up to date")
        case .failed: language.pick("无云可望 · 请检查网络后再试", "No clouds in sight · Check your network and try again")
        case .available(let release): language.pick("新雨已至 · \(release.version)", "Fresh rain is here · \(release.version)")
        case .catching:
            language.pick("正在接雨 · \(Self.percent(progress))%", "Catching rain · \(Self.percent(progress))%")
        case .ready(let release, _): language.pick("新雨已落 · \(release.version)", "\(release.version) is ready")
        }
    }
}

extension DownloadStore {
    func checkForUpdate() {
        guard update != .checking else { return }
        update = .checking
        Task {
            do {
                let release = try await UpdateCheck.latest()
                update = UpdateCheck.isNewer(release.version, than: UpdatePhase.current) ? .available(release) : .latest
            } catch {
                update = .failed(describe(error))
            }
        }
    }

    /// 有新版时接住：拾雨自己就是下载器，安装包直接加进任务列表并跟着进度，发布里没有安装包就打开发布页；
    /// 下好了就打开安装包；正在接雨时不动；其余重新查
    func checkOrCatchUpdate() {
        switch update {
        case .checking, .catching:
            return
        case .available(let release):
            if let installer = release.installer, let id = add(urls: [installer], revealing: true).first {
                update = .catching(release, id)
            } else {
                NSWorkspace.shared.open(release.page)
                update = .idle
            }
        case .ready(let release, let file):
            guard FileManager.default.fileExists(atPath: file.path) else {
                showToast(language.pick("文件已被移动或删除", "File was moved or deleted"), long: true)
                update = .available(release)
                return
            }
            NSWorkspace.shared.open(file)
        default:
            checkForUpdate()
        }
    }

    /// 状态文字；接雨时带上安装包的实时进度
    var updateStatus: String {
        guard case .catching(_, let id) = update else { return update.status(language) }
        return update.status(language, progress: items.first { $0.id == id }?.progress ?? 0)
    }

    /// 任务列表变了就对一下安装包任务：被删退回「新雨已至」，失败转失败，下完转「新雨已落」
    func followInstaller() {
        switch update {
        case .catching(let release, let id):
            guard let item = items.first(where: { $0.id == id }) else { return update = .available(release) }
            if item.status == .completed, let file = item.destination {
                update = .ready(release, file)
            } else if item.status == .failed {
                update = .failed(item.message ?? "")
            }
        case .ready(let release, let file):
            if !items.contains(where: { $0.destination == file }) { update = .available(release) }
        default:
            break
        }
    }
}

/// 更新检测的天气：望云时乌云来回飘，天晴出太阳，有新雨时强调色的雨点落三轮后停住
struct UpdateSky: View {
    let phase: UpdatePhase
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sunUp = false

    var body: some View {
        Group {
            switch phase {
            case .latest:
                Image(systemName: "sun.max")
                    .font(.system(size: 13, weight: .medium))
                    .rotationEffect(.degrees(sunUp ? 0 : -45))
                    .scaleEffect(sunUp ? 1 : 0.6)
                    .opacity(sunUp ? 1 : 0)
                    .onAppear {
                        withAnimation(reduceMotion ? nil : .timingCurve(0.3, 0.7, 0.2, 1, duration: 0.5)) { sunUp = true }
                    }
                    .onDisappear { sunUp = false }
            case .available:
                RainCloud(isRaining: !reduceMotion).foregroundStyle(theme.accent)
            case .catching:
                RainCloud(isRaining: !reduceMotion, isContinuous: true).foregroundStyle(theme.accent)
            case .ready:
                RainCloud(isRaining: false).foregroundStyle(theme.accent)
            case .checking where !reduceMotion:
                cloud.phaseAnimator([-1.5, 1.5]) { content, x in content.offset(x: x) } animation: { _ in .easeInOut(duration: 1.6) }
            default:
                cloud
            }
        }
        .frame(width: 18, height: 16)
        .accessibilityHidden(true)
    }

    private var cloud: some View {
        Image(systemName: "cloud").font(.system(size: 12, weight: .medium))
    }
}

/// 云 + 三滴雨：雨点错开 0.3s 依次下落淡出，落三轮后停在云下；接雨时一直下
private struct RainCloud: View {
    let isRaining: Bool
    var isContinuous = false
    @State private var start = Date()
    @State private var stopped = false
    private static let cycle = 0.9
    private static let rounds = 3.0
    private static let stagger = 0.3
    private static let dropXs: [CGFloat] = [-4, 0, 4]

    var body: some View {
        TimelineView(.animation(paused: !isRaining || stopped)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            ZStack(alignment: .top) {
                Image(systemName: "cloud").font(.system(size: 12, weight: .medium))
                ForEach(0..<3, id: \.self) { index in
                    let drop = drop(index, elapsed: elapsed)
                    Capsule()
                        .frame(width: 1.4, height: 2.6)
                        .rotationEffect(.degrees(16))
                        .offset(x: Self.dropXs[index], y: 11 + (-3 + 6 * drop.progress * drop.progress))
                        .opacity(drop.opacity)
                }
            }
            // 云在上、雨在下，整组比图标框中心偏上一点
            .frame(width: 18, height: 16, alignment: .top)
            .offset(y: 1)
        }
        .task {
            guard isRaining, !isContinuous else { return }
            try? await Task.sleep(for: .seconds(Self.cycle * Self.rounds + Self.stagger * 2))
            stopped = true
        }
    }

    /// 停住或没下雨时雨点挂在中间；还没轮到的雨点先藏着
    private func drop(_ index: Int, elapsed: TimeInterval) -> (progress: Double, opacity: Double) {
        let local = elapsed - Double(index) * Self.stagger
        guard isRaining, !stopped, isContinuous || local < Self.cycle * Self.rounds else { return (0.5, 1) }
        guard local >= 0 else { return (0, 0) }
        let progress = (local / Self.cycle).truncatingRemainder(dividingBy: 1)
        return (progress, progress < 0.3 ? progress / 0.3 : (1 - progress) / 0.7)
    }
}
