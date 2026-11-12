import Foundation

struct APIMessage: Encodable, Equatable {
    let role: String
    let content: String
}

/// Abstraction over the AI backend so the engine can be tested with a mock.
protocol ChatStreaming: Sendable {
    /// Streams reply text fragments. Cancelling the consuming task cancels the request.
    func stream(messages: [APIMessage]) -> AsyncThrowingStream<String, Error>
}

struct OpenRouterClient: ChatStreaming {
    static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    var session: URLSession = .shared
    var model: String = Secrets.model
    var keyProvider: @Sendable () -> String? = { KeyVault.apiKey() }

    private struct RequestBody: Encodable {
        let model: String
        let messages: [APIMessage]
        let stream: Bool
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable { let message: String? }
        let error: Detail?
    }

    func stream(messages: [APIMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let key = keyProvider(), !key.isEmpty else { throw ChatAPIError.missingKey }

                    var request = URLRequest(url: Self.endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 60
                    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("AI Chat", forHTTPHeaderField: "X-Title")
                    request.httpBody = try JSONEncoder().encode(
                        RequestBody(model: model, messages: messages, stream: true)
                    )

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ChatAPIError.invalidResponse }

                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count > 4096 { break }
                        }
                        let message = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error?.message
                        throw ChatAPIError.from(status: http.statusCode, message: message)
                    }

                    var receivedDelta = false
                    for try await line in bytes.lines {
                        switch SSEParser.parse(line: line) {
                        case .delta(let text):
                            receivedDelta = true
                            continuation.yield(text)
                        case .done:
                            continuation.finish()
                            return
                        case .error(let code, let message):
                            throw ChatAPIError.from(status: code ?? 502, message: message)
                        case .ignore:
                            continue
                        }
                    }
                    // Stream ended without [DONE]: fine if we got text, otherwise treat as a failure.
                    if receivedDelta { continuation.finish() } else { throw ChatAPIError.invalidResponse }
                } catch {
                    if let mapped = ChatAPIError.from(transport: error) {
                        continuation.finish(throwing: mapped)
                    } else {
                        continuation.finish(throwing: CancellationError())
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
