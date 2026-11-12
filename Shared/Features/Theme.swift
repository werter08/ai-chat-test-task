import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Design tokens from the design kit (8pt grid, 16px cards, 12px controls, red accent from AccentColor).
enum Theme {
    static let spacing1: CGFloat = 4
    static let spacing2: CGFloat = 8
    static let spacing3: CGFloat = 16
    static let spacing4: CGFloat = 24
    static let spacing5: CGFloat = 32

    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 12
    static let controlHeight: CGFloat = 48

    /// Soft fill for inputs and assistant bubbles; adapts to light/dark.
    static let fill = Color.primary.opacity(0.06)
    static let border = Color.primary.opacity(0.12)
}

extension Font {
    static func display(_ size: CGFloat = 32) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static let heading = Font.system(size: 24, weight: .semibold, design: .rounded)
}

/// Primary (filled accent) and secondary (tinted) 48pt buttons.
struct PrimaryButtonStyle: ButtonStyle {
    var tinted = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tinted ? Color.accentColor : Color.white)
            .frame(maxWidth: .infinity, minHeight: Theme.controlHeight)
            .background(
                tinted ? Color.accentColor.opacity(0.12) : Color.accentColor,
                in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

enum Brand {
    /// Header title from the design kit; change here to rename the in-app brand.
    static let name = "Chatterly"
}

enum Clipboard {
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
