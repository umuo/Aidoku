import Foundation

/// 同一浏览器会话共享验证，不同会话串行展示；取消一个请求不影响其他等待者。
actor VerificationSessionQueue {
    struct Key: Hashable, Sendable {
        let host: String
        let userAgent: String
    }

    private struct Session {
        let id: UUID
        let operation: @Sendable () async throws -> Void
        var waiters: [UUID: CheckedContinuation<Void, Error>]
        var task: Task<Void, Never>?
        var canceling = false
    }

    private var sessions: [Key: Session] = [:]
    private var pending: [Key] = []
    private var active: Key?
    private var cooldown: [Key: Date] = [:]
    private var recentlyVerified: [Key: Date] = [:]
    private let cooldownInterval: TimeInterval

    init(cooldownInterval: TimeInterval = 60) {
        self.cooldownInterval = cooldownInterval
    }

    var waitingRequestCount: Int {
        sessions.values.reduce(0) { $0 + $1.waiters.count }
    }

    func invalidate(key: Key) {
        recentlyVerified[key] = nil
        cooldown[key] = Date().addingTimeInterval(cooldownInterval)
    }

    func verify(key: Key, operation: @escaping @Sendable () async throws -> Void) async throws {
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if let until = recentlyVerified[key], until > Date() {
                    continuation.resume()
                    return
                }
                if let until = cooldown[key], until > Date() {
                    continuation.resume(throwing: WebsiteVerificationError.unavailable)
                    return
                }
                if var session = sessions[key] {
                    guard !session.canceling else {
                        continuation.resume(throwing: WebsiteVerificationError.canceled)
                        return
                    }
                    session.waiters[waiterID] = continuation
                    sessions[key] = session
                } else {
                    sessions[key] = Session(id: UUID(), operation: operation, waiters: [waiterID: continuation])
                    pending.append(key)
                    startNext()
                }
            }
        } onCancel: {
            Task {
                await self.cancel(key: key, waiterID: waiterID)
            }
        }
    }

    private func startNext() {
        guard active == nil, !pending.isEmpty else {
            return
        }
        let key = pending.removeFirst()
        guard var session = sessions[key] else {
            startNext()
            return
        }
        active = key
        let id = session.id
        let operation = session.operation
        session.task = Task {
            let result: Result<Void, Error>
            do {
                try Task.checkCancellation()
                try await operation()
                try Task.checkCancellation()
                result = .success(())
            } catch {
                result = .failure(error)
            }
            finish(key: key, id: id, result: result)
        }
        sessions[key] = session
    }

    private func cancel(key: Key, waiterID: UUID) {
        guard var session = sessions[key], let waiter = session.waiters.removeValue(forKey: waiterID) else {
            return
        }
        waiter.resume(throwing: CancellationError())
        if session.waiters.isEmpty {
            if let task = session.task {
                session.canceling = true
                task.cancel()
                sessions[key] = session
            } else {
                sessions[key] = nil
                pending.removeAll { $0 == key }
            }
        } else {
            sessions[key] = session
        }
    }

    private func finish(key: Key, id: UUID, result: Result<Void, Error>) {
        guard let session = sessions[key], session.id == id else {
            return
        }
        sessions[key] = nil
        if case .failure = result {
            cooldown[key] = Date().addingTimeInterval(cooldownInterval)
            recentlyVerified[key] = nil
        } else {
            cooldown[key] = nil
            // 晚到的旧 403 直接重试，避免刚验证完又弹出同一窗口。
            recentlyVerified[key] = Date().addingTimeInterval(10)
        }
        for waiter in session.waiters.values {
            waiter.resume(with: result)
        }
        if active == key {
            active = nil
        }
        startNext()
    }
}
