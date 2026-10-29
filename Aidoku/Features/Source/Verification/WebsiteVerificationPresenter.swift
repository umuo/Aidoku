import UIKit

@MainActor
enum WebsiteVerificationPresenter {
    private struct Presentation {
        let id: UUID
        let controller: WebsiteVerificationViewController
        let continuation: CheckedContinuation<Void, Error>
    }

    private static var active: Presentation?
    private static var deadline: Task<Void, Never>?

    static func present(policy: WebsiteVerificationPolicy, sourceKey: String, userAgent: String, entryURL: URL) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                guard active == nil,
                      UIApplication.shared.applicationState == .active,
                      let parent = UIApplication.shared.appDelegate?.visibleViewController,
                      parent.presentedViewController == nil,
                      !parent.isBeingDismissed,
                      let sourcePage = parent as? NewSourceViewController,
                      sourcePage.source.key == sourceKey else {
                    // 后台请求或其他页面不弹窗，也不挂起网络等待 UI。
                    continuation.resume(throwing: WebsiteVerificationError.unavailable)
                    return
                }
                let controller = WebsiteVerificationViewController(
                    policy: policy, sourceKey: sourceKey, userAgent: userAgent, entryURL: entryURL
                ) { result in
                    complete(id: id, result: result)
                }
                active = Presentation(id: id, controller: controller, continuation: continuation)
                deadline = Task {
                    do {
                        try await Task.sleep(nanoseconds: 300_000_000_000)
                    } catch {
                        return
                    }
                    guard let presentation = active, presentation.id == id else {
                        return
                    }
                    // 即使系统未成功展示窗口，也必须释放网络请求。
                    complete(id: id, result: .failure(WebsiteVerificationError.timedOut))
                    presentation.controller.cancelVerification()
                }
                parent.present(UINavigationController(rootViewController: controller), animated: true)
            }
        } onCancel: {
            Task { @MainActor in
                if let presentation = active, presentation.id == id {
                    complete(id: id, result: .failure(CancellationError()))
                    presentation.controller.cancelVerification()
                }
            }
        }
    }

    private static func complete(id: UUID, result: Result<Void, Error>) {
        guard let presentation = active, presentation.id == id else {
            return
        }
        active = nil
        deadline?.cancel()
        deadline = nil
        presentation.continuation.resume(with: result)
    }
}
