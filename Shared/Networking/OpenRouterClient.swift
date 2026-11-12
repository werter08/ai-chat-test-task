import Foundation

struct APIMessage: Encodable, Equatable {
    let role: String
    let content: String
    /// `data:image/jpeg;base64,…` URLs. When present the message is encoded in the multi-part (vision) format.
    var imageURLs: [String] = []

    private enum CodingKeys: String, CodingKey { case role, content }

    private struct Part: Encodable {
        struct ImageURL: Encodable { let url: String }
        let type: String
        var text: String?
        var image_url: ImageURL?
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        if imageURLs.isEmpty {
            try container.encode(content, forKey: .content)
        } else {
            var parts = [Part(type: "text", text: content)]
            parts += imageURLs.map { Part(type: "image_url", image_url: .init(url: $0)) }
            try container.encode(parts, forKey: .content)
        }
    }
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
    /// Used instead of `model` whenever a request contains a photo.
    var visionModel: String = Secrets.visionModel
    /// Always sent: without it the provider reserves the model's maximum (131k tokens) and the request is refused
    /// with HTTP 402 when the account cannot afford that, even if the answer would be short.
    nonisolated static let maxTokens = 4096

    var keyProvider: @Sendable () -> String? = { KeyVault.apiKey() }

    private struct RequestBody: Encodable {
        let model: String
        let messages: [APIMessage]
        let stream: Bool
        let max_tokens: Int
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable { let message: String? }
        let error: Detail?
    }

    /// The vision model handles any request that carries a photo; everything else uses the text model.
    nonisolated static func chooseModel(for messages: [APIMessage], text: String, vision: String) -> String {
        messages.contains { !$0.imageURLs.isEmpty } ? vision : text
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
                        RequestBody(
                            model: Self.chooseModel(for: messages, text: model, vision: visionModel),
                            messages: messages,
                            stream: true,
                            max_tokens: Self.maxTokens
                        )
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
                    var receivedReasoning = false
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
                        case .reasoning:
                            receivedReasoning = true
                        case .ignore:
                            continue
                        }
                    }
                    // Stream ended without [DONE]: fine if we got text, otherwise treat as a failure.
                    if receivedDelta { continuation.finish() } else { throw receivedReasoning ? ChatAPIError.noAnswer : ChatAPIError.invalidResponse }
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
