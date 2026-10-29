import Foundation

enum VerificationRequestRecovery {
    static func run(
        original: URLRequest, userAgent: String, policy: WebsiteVerificationPolicy,
        storage: HTTPCookieStorage = .shared,
        verify: @Sendable () async throws -> Void,
        send: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) async throws -> (Data, URLResponse) {
        guard let url = original.url, policy.allowsNavigation(to: url),
              ["GET", "HEAD"].contains((original.httpMethod ?? "GET").uppercased()) else {
            throw WebsiteVerificationError.required
        }
        try Task.checkCancellation()
        try await verify()
        try Task.checkCancellation()
        var request = original
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request = VerificationCookieHeader.applying(to: request, storage: storage)
        // 直接重试一次，不再次进入网络宿主的验证分支。
        let result = try await send(request)
        if let response = result.1 as? HTTPURLResponse,
           response.statusCode == 403 || policy.challengeURL(response: response, data: result.0) != nil {
            throw WebsiteVerificationError.stillBlocked
        }
        return result
    }
}
