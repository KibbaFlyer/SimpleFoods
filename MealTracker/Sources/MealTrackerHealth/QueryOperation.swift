import Foundation

/// Shared native-query lifecycle, tested without invoking HealthKit.
/// Cancellation may arrive before continuation installation, during execute, or at callback completion.
final class QueryOperation<Value>: @unchecked Sendable {
    private let lock=NSLock()
    private var continuation: CheckedContinuation<Value,Error>?
    private var stopAction: (() -> Void)?
    private var started=false
    private var finished=false
    func install(_ value: CheckedContinuation<Value,Error>) -> Bool {
        lock.lock();if finished { lock.unlock();value.resume(throwing:CancellationError());return false }
        continuation=value;lock.unlock();return true
    }
    func start(execute: () -> Void, stop: @escaping () -> Void) {
        lock.lock();guard !finished else { lock.unlock();return };stopAction=stop;lock.unlock()
        execute()
        lock.lock();started=true;let action=finished ? stopAction:nil;if finished { stopAction=nil };lock.unlock()
        action?()
    }
    func cancel() { finish(.failure(CancellationError())) }
    func finish(_ result:Result<Value,Error>) {
        lock.lock();guard !finished else { lock.unlock();return };finished=true
        let continuation=self.continuation;self.continuation=nil
        let action=started ? stopAction:nil;if started { stopAction=nil };lock.unlock()
        action?();continuation?.resume(with:result)
    }
}
