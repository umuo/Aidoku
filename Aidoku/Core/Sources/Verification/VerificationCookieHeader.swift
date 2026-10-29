import Foundation

enum VerificationCookieHeader {
    /// 系统仓库按 URL 筛选路径、域和 Secure；现存会话值优先于请求中残留的旧值。
    static func applying(to original: URLRequest, storage: HTTPCookieStorage = .shared) -> URLRequest {
        guard let url = original.url else {
            return original
        }
        var request = original
        let cookies = (storage.cookies(for: url) ?? []).filter { cookie in
            cookie.expiresDate.map { $0 > Date() } ?? true
        }.sorted { $0.path.count > $1.path.count }
        let storedNames = Set(cookies.map(\.name))
        let explicit = (original.value(forHTTPHeaderField: "Cookie") ?? "")
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { value in
                guard let separator = value.firstIndex(of: "=") else {
                    return false
                }
                let name = value[..<separator].trimmingCharacters(in: .whitespaces)
                return !storedNames.contains(name)
            }
        let values = cookies.map { "\($0.name)=\($0.value)" } + explicit
        request.setValue(values.isEmpty ? nil : values.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        return request
    }

    static func belongsToSite(_ cookie: HTTPCookie, url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }
        let domain = cookie.domain.lowercased()
        if domain.hasPrefix(".") {
            let suffix = String(domain.dropFirst())
            return host == suffix || host.hasSuffix("." + suffix)
        }
        return host == domain
    }
}
