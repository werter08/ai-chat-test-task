import Observation
import SwiftUI

/// App-wide transient confirmation ("Copied to clipboard"). Shown by `ChatScreen`.
@MainActor
@Observable
final class Toast {
    enum Kind { case success, warning }

    private(set) var message: String?
    private(set) var kind: Kind = .success
    @ObservationIgnored private var task: Task<Void, Never>?

    func show(_ text: String, kind: Kind = .success) {
        task?.cancel()
        self.kind = kind
        withAnimation(.snappy) { message = text }
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { self?.message = nil }
        }
    }
}

struct ToastView: View {
    let text: String
    var kind: Toast.Kind = .success

    var body: some View {
        HStack(spacing: 8) {
            // Problems must not look like successes: warnings get their own icon and colour.
            Image(systemName: kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(kind == .success ? Color.green : Color.orange)
            Text(text).font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.85), in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}
