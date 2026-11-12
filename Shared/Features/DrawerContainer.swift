import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Push-style side drawer: the content slides aside while the drawer parallax-slides in beneath it.
/// Interactive — follows the finger, settles with a spring using the drag velocity. A rightward swipe from
/// anywhere opens it (when `swipeEnabled`); tapping or dragging the dimmed content closes it.
/// The dim layer deliberately ignores the safe areas so it covers the whole screen.
///
/// Robustness notes (these fixed "opens once, then never again"):
/// - the drag offset is a `@GestureState`, so it always resets — even if the system cancels the gesture;
/// - the dim layer is never removed from the hierarchy mid-drag (that cancelled the closing gesture and left
///   `isOpen` stuck), it only stops hit-testing when closed.
struct DrawerContainer<Drawer: View, Content: View>: View {
    @Binding var isOpen: Bool
    var swipeEnabled = true
    @ViewBuilder var drawer: () -> Drawer
    @ViewBuilder var content: () -> Content

    @GestureState private var drag: CGFloat = 0

    private static var spring: Animation { .spring(response: 0.38, dampingFraction: 0.86) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width < 600 ? geo.size.width * 0.7 : 380
            let base: CGFloat = isOpen ? width : 0
            let offset = min(max(base + drag, 0), width)
            let progress = width > 0 ? offset / width : 0

            ZStack(alignment: .leading) {
                drawer()
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .offset(x: -(1 - progress) * width * 0.3)
                    .allowsHitTesting(progress > 0.01)
                    .accessibilityHidden(progress < 0.01)
                    .simultaneousGesture(dragGesture(width: width), including: progress > 0.01 ? .all : .subviews)

                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { Rectangle().fill(.background).ignoresSafeArea() }
                    .shadow(color: .black.opacity(0.28 * progress), radius: 16, x: -3)
                    .offset(x: offset)
                    .simultaneousGesture(
                        dragGesture(width: width),
                        including: (!isOpen && swipeEnabled) ? .all : .subviews
                    )

                // Always in the hierarchy (never torn down while a drag is in flight); inert when closed.
                Color.black.opacity(0.22 * progress)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .offset(x: offset)
                    .onTapGesture { setOpen(false) }
                    .gesture(dragGesture(width: width))
                    .allowsHitTesting(progress > 0.001)
                    .accessibilityHidden(progress < 0.001)
                    .accessibilityLabel("Close menu")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .onChange(of: isOpen) { _, open in if open { Self.dismissKeyboard() } }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($drag) { value, state, _ in
                // Only mostly-horizontal drags move the drawer (vertical ones belong to scroll views).
                guard isHorizontal(value.translation) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard isHorizontal(value.translation) else { return }
                let base: CGFloat = isOpen ? width : 0
                let projected = base + value.predictedEndTranslation.width
                withAnimation(Self.spring) { isOpen = projected > width / 2 }
            }
    }

    private func isHorizontal(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height) * 1.5
    }

    private func setOpen(_ open: Bool) {
        withAnimation(Self.spring) { isOpen = open }
    }

    private static func dismissKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}
