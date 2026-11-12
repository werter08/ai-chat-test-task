import Foundation

/// Reads the API key embedded by `scripts/obfuscate_key.swift`.
/// The key is XOR-ed with a random salt: this hides it from `strings`/grep, it is NOT encryption.
enum KeyVault {
    static func apiKey() -> String? {
        reveal(blob: Secrets.blob, salt: Secrets.salt)
    }

    static func reveal(blob: [UInt8], salt: [UInt8]) -> String? {
        guard !blob.isEmpty, !salt.isEmpty else { return nil }
        let bytes = blob.enumerated().map { $0.element ^ salt[$0.offset % salt.count] }
        return String(bytes: bytes, encoding: .utf8)
    }

    /// Same transform as the generator script; used by tests.
    static func conceal(_ text: String, salt: [UInt8]) -> [UInt8] {
        text.utf8.enumerated().map { $0.element ^ salt[$0.offset % salt.count] }
    }
}
