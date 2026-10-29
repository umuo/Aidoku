import Foundation

enum WebsiteVerificationError: Error, LocalizedError, Sendable, Equatable {
    case required
    case canceled
    case timedOut
    case unavailable
    case stillBlocked

    var errorDescription: String? {
        let key: String
        switch self {
        case .required:
            key = "WEBSITE_VERIFICATION_REQUIRED"
        case .canceled:
            key = "WEBSITE_VERIFICATION_CANCELED"
        case .timedOut:
            key = "WEBSITE_VERIFICATION_EXPIRED"
        case .unavailable:
            key = "WEBSITE_VERIFICATION_UNAVAILABLE"
        case .stillBlocked:
            key = "WEBSITE_VERIFICATION_STILL_BLOCKED"
        }
        return NSLocalizedString(key, comment: "")
    }
}
