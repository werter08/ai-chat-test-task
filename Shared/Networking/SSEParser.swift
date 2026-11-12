import Foundation

/// Parses one line of an OpenAI-compatible `text/event-stream` (as served by OpenRouter).
enum SSEParser {
    enum Event: Equatable {
        case delta(String)
        case reasoning
        case done
        case error(code: Int?, message: String)
        case ignore
    }

    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String?; let reasoning: String? }
            let delta: Delta?
            let finish_reason: String?
        }
        struct Failure: Decodable {
            let code: Int?
            let message: String?
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                code = (try? c.decode(Int.self, forKey: .code)) ?? (try? c.decode(String.self, forKey: .code)).flatMap(Int.init)
                message = try? c.decode(String.self, forKey: .message)
            }
            enum CodingKeys: String, CodingKey { case code, message }
        }
        let choices: [Choice]?
        let error: Failure?
    }

    static func parse(line: String) -> Event {
        // Comment/keep-alive lines such as ": OPENROUTER PROCESSING".
        guard !line.hasPrefix(":"), line.hasPrefix("data:") else { return .ignore }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data) else { return .ignore }
        if let error = chunk.error {
            return .error(code: error.code, message: error.message ?? "Unknown provider error")
        }
        if let text = chunk.choices?.first?.delta?.content, !text.isEmpty {
            return .delta(text)
        }
        if let thinking = chunk.choices?.first?.delta?.reasoning, !thinking.isEmpty {
            return .reasoning
        }
        return .ignore
    }
}
