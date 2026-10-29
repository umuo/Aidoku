import Foundation

/// 包子漫画的验证入口与只读探测。只接受已适配的站点，避免将普通 403 当作验证。
struct WebsiteVerificationPolicy: Sendable {
    let baseURL: URL

    static func supports(sourceKey: String, url: URL) -> Bool {
        sourceKey == "zh.baozimh1"
            && url.scheme?.lowercased() == "https"
            && ["www.baozimh.com", "baozimh.com"].contains(url.host?.lowercased() ?? "")
            && (url.port == nil || url.port == 443)
            && url.user == nil
            && url.password == nil
    }

    init?(sourceKey: String, url: URL) {
        guard Self.supports(sourceKey: sourceKey, url: url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        guard let baseURL = components.url else {
            return nil
        }
        self.baseURL = baseURL
    }

    var probeRequest: URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/bzmhq/amp_comic_list"
        components.queryItems = [
            URLQueryItem(name: "type", value: "all"),
            URLQueryItem(name: "region", value: "all"),
            URLQueryItem(name: "state", value: "all"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "language", value: "tw")
        ]
        return URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    }

    func allowsNavigation(to url: URL) -> Bool {
        Self.supports(sourceKey: "zh.baozimh1", url: url)
            && url.host?.lowercased() == baseURL.host?.lowercased()
    }

    func challengeURL(response: HTTPURLResponse, data: Data) -> URL? {
        guard response.statusCode == 403,
              let responseURL = response.url,
              allowsNavigation(to: responseURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["error"] as? String == "challenge_required",
              let path = object["challenge_url"] as? String,
              let url = URL(string: path, relativeTo: responseURL)?.absoluteURL,
              allowsNavigation(to: url),
              url.path == "/__gatekeeper_challenge/start" else {
            return nil
        }
        return url
    }

    func isSuccessfulProbe(response: URLResponse, data: Data) -> Bool {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let url = response.url,
              allowsNavigation(to: url),
              url.path == probeRequest.url?.path,
              response.mimeType?.lowercased() == "application/json",
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["error"] == nil,
              let items = object["items"] as? [[String: Any]] else {
            return false
        }
        return items.allSatisfy { item in
            item["comic_id"] is String && item["name"] is String && item["topic_img"] is String
        }
    }
}
