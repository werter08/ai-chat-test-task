import Foundation

/// Every failure the chat can surface to the user. All of them are retryable from the UI.
enum ChatAPIError: Error, Equatable, LocalizedError {
    case missingKey
    case offline
    case timeout
    case unauthorized
    case insufficientCredits
    case forbidden(String?)
    case rateLimited
    case modelUnavailable
    case badRequest(String?)
    case server(String?)
    case invalidResponse
    /// The last user message never got an answer (e.g. the app was closed mid-request).
    case noResponse

    var title: String {
        switch self {
        case .missingKey: "API key missing"
        case .offline: "No internet connection"
        case .timeout: "Request timed out"
        case .unauthorized: "API key rejected"
        case .insufficientCredits: "API limit reached"
        case .forbidden: "Access denied"
        case .rateLimited: "Too many requests"
        case .modelUnavailable: "Model unavailable"
        case .badRequest: "Request failed"
        case .server: "Server error"
        case .invalidResponse: "Unexpected response"
        case .noResponse: "No reply received"
        }
    }

    var message: String {
        switch self {
        case .missingKey: "This build has no API key embedded. Add it to .env and rebuild."
        case .offline: "Check your connection and try again."
        case .timeout: "The server took too long to respond."
        case .unauthorized: "The embedded API key is invalid or disabled."
        case .insufficientCredits: "The free quota for this API key is used up. Try again later."
        case .forbidden(let detail): detail ?? "The key's spend limit is reached or access is blocked."
        case .rateLimited: "The free model is rate limited right now. Wait a moment and retry."
        case .modelUnavailable: "No provider can serve this model at the moment."
        case .badRequest(let detail): detail ?? "The server rejected the request."
        case .server(let detail): detail ?? "The AI provider failed to generate a reply."
        case .invalidResponse: "The server returned data the app could not read."
        case .noResponse: "The assistant did not answer this message."
        }
    }

    var errorDescription: String? { "\(title). \(message)" }

    /// Maps an HTTP status (and optional provider message) to an error.
    static func from(status: Int, message: String?) -> ChatAPIError {
        switch status {
        case 400: .badRequest(message)
        case 401: .unauthorized
        case 402: .insufficientCredits
        case 403: .forbidden(message)
        case 404: .modelUnavailable
        case 408: .timeout
        case 429: .rateLimited
        case 500...599: .server(message)
        default: .server(message)
        }
    }

    /// Maps a transport-level error. Returns `nil` for cancellation (not a failure).
    static func from(transport error: Error) -> ChatAPIError? {
        if error is CancellationError { return nil }
        if let known = error as? ChatAPIError { return known }
        guard let url = error as? URLError else { return .server(nil) }
        switch url.code {
        case .cancelled: return nil
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff:
            return .offline
        case .timedOut: return .timeout
        default: return .server(nil)
        }
    }
}
