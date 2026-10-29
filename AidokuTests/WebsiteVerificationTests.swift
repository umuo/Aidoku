import Foundation
import Testing
@testable import Aidoku

@Suite struct WebsiteVerificationTests {
    private let baseURL = URL(string: "https://www.baozimh.com")!

    @Test func limitsSourceAndOrigin() throws {
        #expect(WebsiteVerificationPolicy(sourceKey: "zh.baozimh2", url: baseURL) == nil)
        for value in ["http://www.baozimh.com", "https://www.baozimh.com.evil.test", "https://evilbaozimh.com",
                      "https://www.baozimh.com:8443", "https://user@www.baozimh.com"] {
            #expect(WebsiteVerificationPolicy(sourceKey: "zh.baozimh1", url: URL(string: value)!) == nil)
        }
    }

    @Test func recognizesOnlyExplicitChallenge() throws {
        let policy = try #require(WebsiteVerificationPolicy(sourceKey: "zh.baozimh1", url: baseURL))
        let response = HTTPURLResponse(url: policy.probeRequest.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
        let data = Data(#"{"error":"challenge_required","challenge_url":"/__gatekeeper_challenge/start?return=%2F"}"#.utf8)
        #expect(policy.challengeURL(response: response, data: data)?.path == "/__gatekeeper_challenge/start")
        #expect(policy.challengeURL(response: response, data: Data("Forbidden".utf8)) == nil)
        #expect(policy.challengeURL(response: response, data: Data(#"{"error":"denied"}"#.utf8)) == nil)
        for path in ["https://evil.test/__gatekeeper_challenge/start", "javascript:alert(1)", "//evil.test/__gatekeeper_challenge/start", "/other"] {
            let invalid = try JSONSerialization.data(withJSONObject: ["error": "challenge_required", "challenge_url": path])
            #expect(policy.challengeURL(response: response, data: invalid) == nil)
        }
    }

    @Test func validatesAPIInsteadOfWebPage() throws {
        let policy = try #require(WebsiteVerificationPolicy(sourceKey: "zh.baozimh1", url: baseURL))
        func response(_ url: URL, status: Int = 200, mime: String = "application/json") -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": mime])!
        }
        let url = policy.probeRequest.url!
        #expect(policy.isSuccessfulProbe(response: response(url), data: Data(#"{"items":[]}"#.utf8)))
        #expect(policy.isSuccessfulProbe(response: response(url), data: Data(#"{"items":[{"comic_id":"x","name":"title","topic_img":"x.jpg"}]}"#.utf8)))
        for body in ["<html>正在验证浏览器</html>", #"{"error":"challenge_required","items":[]}"#, #"{"items":[{"name":"wrong"}]}"#, #"{"items":"wrong"}"#] {
            #expect(!policy.isSuccessfulProbe(response: response(url), data: Data(body.utf8)))
        }
        #expect(!policy.isSuccessfulProbe(response: response(url, status: 403), data: Data(#"{"items":[]}"#.utf8)))
        #expect(!policy.isSuccessfulProbe(response: response(url, mime: "text/html"), data: Data(#"{"items":[]}"#.utf8)))
        #expect(!policy.isSuccessfulProbe(response: response(baseURL), data: Data(#"{"items":[]}"#.utf8)))
    }

    @Test func rebuildsCookiesWithoutStaleSessionValues() {
        let storage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: UUID().uuidString)
        defer {
            for cookie in storage.cookies ?? [] {
                storage.deleteCookie(cookie)
            }
        }
        let cookie = HTTPCookie(properties: [.domain: ".baozimh.com", .path: "/", .name: "gate", .value: "new", .secure: "TRUE"])!
        storage.setCookie(cookie)
        var request = URLRequest(url: baseURL)
        request.setValue("gate=old; preference=tw", forHTTPHeaderField: "Cookie")
        let updated = VerificationCookieHeader.applying(to: request, storage: storage)
        #expect(updated.value(forHTTPHeaderField: "Cookie") == "gate=new; preference=tw")
        #expect(VerificationCookieHeader.applying(to: updated, storage: storage).value(forHTTPHeaderField: "Cookie") == "gate=new; preference=tw")
        #expect(!VerificationCookieHeader.belongsToSite(cookie, url: URL(string: "https://evilbaozimh.com")!))
        #expect(VerificationCookieHeader.belongsToSite(cookie, url: baseURL))
    }

    @Test func respectsCookieURLScope() {
        let storage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: UUID().uuidString)
        defer {
            for cookie in storage.cookies ?? [] {
                storage.deleteCookie(cookie)
            }
        }
        for (path, name, secure) in [("/api", "api", "TRUE"), ("/reader", "reader", "FALSE")] {
            storage.setCookie(HTTPCookie(properties: [.domain: ".baozimh.com", .path: path, .name: name, .value: "yes", .secure: secure])!)
        }
        func header(_ url: String) -> String? {
            VerificationCookieHeader.applying(to: URLRequest(url: URL(string: url)!), storage: storage).value(forHTTPHeaderField: "Cookie")
        }
        #expect(header("https://www.baozimh.com/api/list") == "api=yes")
        #expect(header("https://www.baozimh.com/apix") == nil)
        #expect(header("http://www.baozimh.com/api/list") == nil)
        #expect(header("https://evilbaozimh.com/api/list") == nil)
    }
}
