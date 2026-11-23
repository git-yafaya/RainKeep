// 自动重试策略：哪些错误值得重试、每次等多久
import Foundation

public enum Retry {
    /// 连续失败超过这个次数就标成失败，交给用户手动重试
    public static let maxAttempts = 10
    private static let maxDelaySeconds = 60

    private static let transientCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
        .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
    ]

    /// 网络抖动、服务器临时故障（5xx、429）、连接提前断开可以重试；404 这类明确拒绝不重试
    public static func isTransient(_ error: any Error) -> Bool {
        if let error = error as? URLError { return transientCodes.contains(error.code) }
        switch error as? EngineError {
        case .status(let code): return code == 429 || (500..<600).contains(code)
        case .incomplete: return true
        default: return false
        }
    }

    /// 第 n 次重试前等待 2、4、8……秒，最多 60 秒
    public static func delay(attempt: Int) -> Duration {
        .seconds(min(maxDelaySeconds, 1 << min(max(attempt, 1), 6)))
    }
}
