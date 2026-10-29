import Foundation

enum VerificationEligibility {
    private static func key(sourceKey: String, host: String) -> String {
        "\(sourceKey).websiteVerification.confirmedUA.\(host.lowercased())"
    }

    static func record(sourceKey: String, host: String, userAgent: String, defaults: UserDefaults = .standard) {
        defaults.set(userAgent, forKey: key(sourceKey: sourceKey, host: host))
    }

    static func isEnabled(sourceKey: String, host: String, userAgent: String, defaults: UserDefaults = .standard) -> Bool {
        // 仅表示本设备曾用这个浏览器环境完成手动闭环，不表示当前验证仍然有效。
        !userAgent.isEmpty && defaults.string(forKey: key(sourceKey: sourceKey, host: host)) == userAgent
    }

    static func reset(sourceKey: String, defaults: UserDefaults = .standard) {
        let prefix = "\(sourceKey).websiteVerification.confirmedUA."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
