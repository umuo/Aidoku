import Foundation

enum WebsiteVerificationService {
    private static let queue = VerificationSessionQueue()

    static func shouldHandle(sourceKey: String, response: HTTPURLResponse, data: Data) -> Bool {
        guard let url = response.url, let policy = WebsiteVerificationPolicy(sourceKey: sourceKey, url: url) else {
            return false
        }
        return policy.challengeURL(response: response, data: data) != nil
    }

    static func recover(
        sourceKey: String, original: URLRequest, effective: URLRequest, response: HTTPURLResponse, data: Data
    ) async throws -> (Data, URLResponse) {
        guard let url = response.url,
              let host = url.host?.lowercased(),
              let policy = WebsiteVerificationPolicy(sourceKey: sourceKey, url: url),
              let entryURL = policy.challengeURL(response: response, data: data),
              let requestURL = original.url, policy.allowsNavigation(to: requestURL),
              ["GET", "HEAD"].contains((original.httpMethod ?? "GET").uppercased()),
              let userAgent = effective.value(forHTTPHeaderField: "User-Agent"),
              VerificationEligibility.isEnabled(sourceKey: sourceKey, host: host, userAgent: userAgent) else {
            throw WebsiteVerificationError.required
        }
        let key = VerificationSessionQueue.Key(host: host, userAgent: userAgent)
        do {
            return try await VerificationRequestRecovery.run(original: original, userAgent: userAgent, policy: policy) {
                try await queue.verify(key: key) {
                    try await WebsiteVerificationPresenter.present(
                        policy: policy, sourceKey: sourceKey, userAgent: userAgent, entryURL: entryURL
                    )
                }
            }
        } catch {
            if let error = error as? WebsiteVerificationError, error == .stillBlocked {
                await queue.invalidate(key: key)
            }
            throw error
        }
    }
}
