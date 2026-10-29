import WebKit

@MainActor
enum VerificationCookieBridge {
    static func importCookies(for url: URL, into store: WKHTTPCookieStore, storage: HTTPCookieStorage = .shared) async {
        // WebKit 的持久化状态可能比原生仓库更新，同一 Cookie 已存在时保留网页值。
        let existing = await store.allCookies()
        for cookie in storage.cookies ?? [] {
            guard VerificationCookieHeader.belongsToSite(cookie, url: url),
                  cookie.expiresDate.map({ $0 > Date() }) ?? true else {
                continue
            }
            let exists = existing.contains {
                $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path
            }
            if !exists {
                await store.setCookie(cookie)
            }
        }
    }

    static func exportCookies(for url: URL, from store: WKHTTPCookieStore, storage: HTTPCookieStorage = .shared) async {
        let cookies = await store.allCookies().filter { VerificationCookieHeader.belongsToSite($0, url: url) }
        // 以 WebKit 为本站会话的权威状态，同时传播网页删除的 Cookie。
        for old in storage.cookies ?? [] {
            if VerificationCookieHeader.belongsToSite(old, url: url) {
                storage.deleteCookie(old)
            }
        }
        for cookie in cookies {
            if cookie.expiresDate.map({ $0 > Date() }) ?? true {
                storage.setCookie(cookie)
            }
        }
    }
}
