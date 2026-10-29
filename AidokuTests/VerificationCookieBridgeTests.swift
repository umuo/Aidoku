import Foundation
import Testing
import WebKit
@testable import Aidoku

@Suite struct VerificationCookieBridgeTests {
    @Test @MainActor func preservesWebKitStateAndExportsDeletion() async throws {
        let url = URL(string: "https://www.baozimh.com")!
        let storage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: UUID().uuidString)
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let store = dataStore.httpCookieStore
        defer {
            for cookie in storage.cookies ?? [] {
                storage.deleteCookie(cookie)
            }
        }
        func cookie(_ value: String, domain: String = ".baozimh.com", path: String = "/") -> HTTPCookie {
            HTTPCookie(properties: [.domain: domain, .path: path, .name: "gate", .value: value,
                                    .secure: "TRUE", .expires: Date().addingTimeInterval(3600)])!
        }
        let native = cookie("old")
        let browser = cookie("new")
        let unrelated = cookie("private", domain: ".example.com")
        storage.setCookie(native)
        storage.setCookie(unrelated)
        await store.setCookie(browser)
        await VerificationCookieBridge.importCookies(for: url, into: store, storage: storage)
        var webCookies = await store.allCookies()
        #expect(webCookies.count == 1)
        #expect(webCookies.first?.value == "new")
        await VerificationCookieBridge.exportCookies(for: url, from: store, storage: storage)
        let exported = try #require(storage.cookies(for: url)?.first)
        #expect(exported.value == "new")
        #expect(exported.isSecure)
        #expect(exported.path == browser.path)
        #expect(exported.expiresDate != nil)
        #expect(storage.cookies(for: URL(string: "https://www.example.com")!)?.first?.value == "private")
        for cookie in webCookies {
            await store.deleteCookie(cookie)
        }
        await VerificationCookieBridge.exportCookies(for: url, from: store, storage: storage)
        #expect(storage.cookies(for: url)?.isEmpty ?? true)
        webCookies = await store.allCookies()
        #expect(webCookies.isEmpty)
        #expect(!dataStore.isPersistent)
    }
}
