// 通过 URLSession 委托接收数据块，将任务取消传递给网络请求。
import Foundation

// 每个请求独占一个委托，同一任务的回调按响应、数据、完成的顺序交付。
final class EngineTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias Check = @Sendable (URLResponse) throws -> Void
    typealias Receive = @Sendable (Data) throws -> Bool

    private let check: Check
    private let receive: Receive
    private let completion: CheckedContinuation<Void, any Error>
    private var failure: (any Error)?
    private var reachedSplitBoundary = false

    private init(check: @escaping Check, receive: @escaping Receive,
                 completion: CheckedContinuation<Void, any Error>) {
        self.check = check
        self.receive = receive
        self.completion = completion
    }

    static func run(_ request: URLRequest, session: URLSession, check: @escaping Check,
                    receive: @escaping Receive) async throws {
        try Task.checkCancellation()
        let task = session.dataTask(with: request)
        let lock = NSLock()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    task.delegate = EngineTransfer(check: check, receive: receive, completion: continuation)
                    task.resume()
                    if Task.isCancelled { task.cancel() }
                }
            }
        } onCancel: {
            // 启动前取消由上面的检查处理，避免错过任务的完成回调。
            lock.withLock { if task.delegate is EngineTransfer { task.cancel() } }
        }
        try Task.checkCancellation()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        do {
            try check(response)
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil, !reachedSplitBoundary else { return }
        do {
            reachedSplitBoundary = try receive(data)
            if reachedSplitBoundary { dataTask.cancel() }
        } catch {
            failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if reachedSplitBoundary, (error as? URLError)?.code == .cancelled { completion.resume() }
        else if let error = failure ?? error { completion.resume(throwing: error) }
        else { completion.resume() }
    }
}
