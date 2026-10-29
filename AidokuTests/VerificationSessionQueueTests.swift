import Foundation
import Testing
@testable import Aidoku

@Suite(.timeLimit(.minutes(1))) struct VerificationSessionQueueTests {
    private actor Gate {
        var starts = 0
        var wasCanceled = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func run() async {
            starts += 1
            await withCheckedContinuation { waiters.append($0) }
            wasCanceled = Task.isCancelled
        }

        func release() {
            let current = waiters
            waiters = []
            for waiter in current {
                waiter.resume()
            }
        }
    }

    private let key = VerificationSessionQueue.Key(host: "www.baozimh.com", userAgent: "test")

    private func waitForCount(_ count: Int, queue: VerificationSessionQueue) async {
        while await queue.waitingRequestCount != count {
            await Task.yield()
        }
    }

    @Test func sharesOneVerificationAndKeepsOtherWaitersOnCancellation() async throws {
        let queue = VerificationSessionQueue()
        let gate = Gate()
        let first = Task { try await queue.verify(key: key) { await gate.run() } }
        let second = Task { try await queue.verify(key: key) { await gate.run() } }
        await waitForCount(2, queue: queue)
        while await gate.starts == 0 {
            await Task.yield()
        }
        #expect(await gate.starts == 1)
        first.cancel()
        await waitForCount(1, queue: queue)
        await gate.release()
        do {
            try await first.value
            Issue.record("Canceled waiter unexpectedly succeeded")
        } catch is CancellationError {
            // 另一个请求仍继续等待原来的同一次验证。
        }
        try await second.value
        #expect(await gate.starts == 1)
        #expect(await queue.waitingRequestCount == 0)
    }

    @Test func serializesDifferentHosts() async throws {
        let queue = VerificationSessionQueue()
        let firstGate = Gate()
        let secondGate = Gate()
        let first = Task { try await queue.verify(key: key) { await firstGate.run() } }
        while await firstGate.starts == 0 {
            await Task.yield()
        }
        let other = VerificationSessionQueue.Key(host: "baozimh.com", userAgent: "test")
        let second = Task { try await queue.verify(key: other) { await secondGate.run() } }
        await waitForCount(2, queue: queue)
        #expect(await secondGate.starts == 0)
        await firstGate.release()
        try await first.value
        while await secondGate.starts == 0 {
            await Task.yield()
        }
        await secondGate.release()
        try await second.value
    }

    @Test func failureReleasesEveryWaiterAndAppliesCooldown() async throws {
        let queue = VerificationSessionQueue()
        do {
            try await queue.verify(key: key) { throw WebsiteVerificationError.timedOut }
            Issue.record("Timeout unexpectedly succeeded")
        } catch let error as WebsiteVerificationError {
            #expect(error == .timedOut)
        }
        do {
            try await queue.verify(key: key) { Issue.record("Cooldown must not open another popup") }
            Issue.record("Cooldown unexpectedly succeeded")
        } catch let error as WebsiteVerificationError {
            #expect(error == .unavailable)
        }
        #expect(await queue.waitingRequestCount == 0)
    }

    @Test func alreadyCanceledRequestNeverPresents() async throws {
        let queue = VerificationSessionQueue()
        let gate = Gate()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await queue.verify(key: key) { await gate.run() }
        }
        do {
            try await task.value
            Issue.record("Canceled request unexpectedly succeeded")
        } catch is CancellationError {
            #expect(await gate.starts == 0)
        }
    }

    @Test func lateResponsesReuseSuccessUntilInvalidated() async throws {
        let queue = VerificationSessionQueue()
        try await queue.verify(key: key) {}
        try await queue.verify(key: key) { Issue.record("Late response reopened a verified session") }
        await queue.invalidate(key: key)
        do {
            try await queue.verify(key: key) { Issue.record("Failed retry reopened verification") }
            Issue.record("Invalidated verification unexpectedly succeeded")
        } catch let error as WebsiteVerificationError {
            #expect(error == .unavailable)
        }
    }

    @Test func cancelsQueuedSessionWithoutOpeningIt() async throws {
        let queue = VerificationSessionQueue()
        let gate = Gate()
        let first = Task { try await queue.verify(key: key) { await gate.run() } }
        while await gate.starts == 0 {
            await Task.yield()
        }
        let other = VerificationSessionQueue.Key(host: "baozimh.com", userAgent: "other")
        let second = Task { try await queue.verify(key: other) { Issue.record("Canceled queued session was opened") } }
        await waitForCount(2, queue: queue)
        second.cancel()
        do {
            try await second.value
            Issue.record("Queued cancellation unexpectedly succeeded")
        } catch is CancellationError {
            // 尚未展示的会话从队列移除，不影响正在进行的验证。
        }
        await gate.release()
        try await first.value
        #expect(await queue.waitingRequestCount == 0)
    }

    @Test func lastWaiterCancelsUnderlyingVerification() async throws {
        let queue = VerificationSessionQueue()
        let gate = Gate()
        let task = Task { try await queue.verify(key: key) { await gate.run() } }
        while await gate.starts == 0 {
            await Task.yield()
        }
        task.cancel()
        do {
            try await task.value
            Issue.record("Last waiter cancellation unexpectedly succeeded")
        } catch is CancellationError {
            // 网络等待立即结束，底层验证也收到取消信号。
        }
        await gate.release()
        let other = VerificationSessionQueue.Key(host: "other", userAgent: "test")
        try await queue.verify(key: other) {}
        #expect(await gate.wasCanceled)
        #expect(await queue.waitingRequestCount == 0)
    }

    @Test func failedSharedVerificationReleasesAllWaiters() async throws {
        let queue = VerificationSessionQueue()
        let gate = Gate()
        let first = Task {
            try await queue.verify(key: key) {
                await gate.run()
                throw WebsiteVerificationError.timedOut
            }
        }
        while await gate.starts == 0 {
            await Task.yield()
        }
        let second = Task { try await queue.verify(key: key) { Issue.record("Shared verification duplicated") } }
        await waitForCount(2, queue: queue)
        await gate.release()
        for task in [first, second] {
            do {
                try await task.value
                Issue.record("Shared failure unexpectedly succeeded")
            } catch let error as WebsiteVerificationError {
                #expect(error == .timedOut)
            }
        }
        #expect(await queue.waitingRequestCount == 0)
    }

    @Test func eligibilityRequiresSameDeviceBrowserAndResets() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!VerificationEligibility.isEnabled(sourceKey: "source", host: "host", userAgent: "ua", defaults: defaults))
        VerificationEligibility.record(sourceKey: "source", host: "host", userAgent: "ua", defaults: defaults)
        #expect(VerificationEligibility.isEnabled(sourceKey: "source", host: "host", userAgent: "ua", defaults: defaults))
        #expect(!VerificationEligibility.isEnabled(sourceKey: "source", host: "host", userAgent: "new", defaults: defaults))
        #expect(!VerificationEligibility.isEnabled(sourceKey: "other", host: "host", userAgent: "ua", defaults: defaults))
        VerificationEligibility.reset(sourceKey: "source", defaults: defaults)
        #expect(!VerificationEligibility.isEnabled(sourceKey: "source", host: "host", userAgent: "ua", defaults: defaults))
    }
}
