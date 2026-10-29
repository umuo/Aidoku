import Foundation
import Testing
@testable import Aidoku

@Suite struct VerificationRequestRecoveryTests {
    private actor Transport {
        var verifications = 0
        var requests: [URLRequest] = []

        func verify() {
            verifications += 1
        }

        func send(_ request: URLRequest, blocked: Bool) -> (Data, URLResponse) {
            requests.append(request)
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: blocked ? 403 : 200,
                                                   httpVersion: nil, headerFields: nil)!)
        }
    }

    @Test func rebuildsOnceAndPreservesOriginalRequest() async throws {
        let policy = try #require(WebsiteVerificationPolicy(sourceKey: "zh.baozimh1", url: URL(string: "https://www.baozimh.com")!))
        var original = policy.probeRequest
        original.httpMethod = "HEAD"
        original.setValue("original", forHTTPHeaderField: "X-Context")
        let transport = Transport()
        _ = try await VerificationRequestRecovery.run(
            original: original, userAgent: "browser", policy: policy,
            storage: .sharedCookieStorage(forGroupContainerIdentifier: UUID().uuidString)
        ) {
            await transport.verify()
        } send: {
            await transport.send($0, blocked: false)
        }
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "HEAD")
        #expect(request.url == original.url)
        #expect(request.value(forHTTPHeaderField: "X-Context") == "original")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "browser")
        #expect(await transport.requests.count == 1)
        #expect(await transport.verifications == 1)
    }

    @Test func stillBlockedDoesNotReopenVerification() async throws {
        let policy = try #require(WebsiteVerificationPolicy(sourceKey: "zh.baozimh1", url: URL(string: "https://www.baozimh.com")!))
        let transport = Transport()
        do {
            _ = try await VerificationRequestRecovery.run(
                original: policy.probeRequest, userAgent: "browser", policy: policy,
                storage: .sharedCookieStorage(forGroupContainerIdentifier: UUID().uuidString)
            ) {
                await transport.verify()
            } send: {
                await transport.send($0, blocked: true)
            }
            Issue.record("A blocked retry must fail")
        } catch let error as WebsiteVerificationError {
            #expect(error == .stillBlocked)
        }
        #expect(await transport.requests.count == 1)
        #expect(await transport.verifications == 1)
    }

    @Test func postNeverPresentsOrReplays() async throws {
        let policy = try #require(WebsiteVerificationPolicy(sourceKey: "zh.baozimh1", url: URL(string: "https://www.baozimh.com")!))
        var original = policy.probeRequest
        original.httpMethod = "POST"
        original.httpBody = Data("action=change".utf8)
        let transport = Transport()
        do {
            _ = try await VerificationRequestRecovery.run(
                original: original, userAgent: "browser", policy: policy,
                storage: .sharedCookieStorage(forGroupContainerIdentifier: UUID().uuidString)
            ) {
                await transport.verify()
            } send: {
                await transport.send($0, blocked: false)
            }
            Issue.record("POST must not be replayed")
        } catch let error as WebsiteVerificationError {
            #expect(error == .required)
        }
        #expect(await transport.requests.isEmpty)
        #expect(await transport.verifications == 0)
    }

    @Test func canceledVerificationNeverReplays() async throws {
        let policy = try #require(WebsiteVerificationPolicy(sourceKey: "zh.baozimh1", url: URL(string: "https://www.baozimh.com")!))
        let transport = Transport()
        do {
            _ = try await VerificationRequestRecovery.run(
                original: policy.probeRequest, userAgent: "browser", policy: policy,
                storage: .sharedCookieStorage(forGroupContainerIdentifier: UUID().uuidString)
            ) {
                throw WebsiteVerificationError.canceled
            } send: {
                await transport.send($0, blocked: false)
            }
            Issue.record("Canceled verification must fail")
        } catch let error as WebsiteVerificationError {
            #expect(error == .canceled)
        }
        #expect(await transport.requests.isEmpty)
    }
}
