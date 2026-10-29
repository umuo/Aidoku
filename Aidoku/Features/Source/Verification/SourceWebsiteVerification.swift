import AidokuRunner
import SwiftUI

extension AidokuRunner.Source {
    var websiteVerificationPolicy: WebsiteVerificationPolicy? {
        // 包子漫画旧源使用固定主机；不在网络桥阻塞期间调用源 actor。
        urls.compactMap { WebsiteVerificationPolicy(sourceKey: key, url: $0) }.first
    }

    @MainActor
    func websiteVerificationController() -> UINavigationController? {
        guard let policy = websiteVerificationPolicy else {
            return nil
        }
        let controller = WebsiteVerificationViewController(
            policy: policy, sourceKey: key, userAgent: legacySource?.netModule.userAgent
        )
        return UINavigationController(rootViewController: controller)
    }
}

struct SourceWebsiteVerificationSheet: UIViewControllerRepresentable {
    let source: AidokuRunner.Source

    func makeUIViewController(context: Context) -> UINavigationController {
        source.websiteVerificationController() ?? UINavigationController()
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
