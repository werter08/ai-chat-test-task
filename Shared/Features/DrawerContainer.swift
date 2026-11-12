import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Live state of a drawer drag.
struct DrawerDrag: Equatable {
    /// How far the drawer has been dragged from where it was (follows the finger 1:1 once locked).
    var offset: CGFloat = 0
    /// True once the drag has been recognised as a horizontal drawer swipe.
    var locked = false
    /// Finger travel at the moment of locking: the drawer starts moving from here, so it never leaps.
    var origin: CGFloat = 0
}

/// The drag arithmetic, kept pure so it can be unit-tested.
enum DrawerMath {
    static let lockDistance: CGFloat = 8

    /// A drag counts as a drawer swipe once it is clearly more horizontal than vertical.
    static func isHorizontal(_ translation: CGSize) -> Bool {
        abs(translation.width) > lockDistance && abs(translation.width) > abs(translation.height) * 1.2
    }

    /// Advances the live drag state. Before the lock nothing moves; at the lock the current finger travel becomes the
    /// origin (no jump); afterwards the drawer follows the finger exactly.
    static func update(_ state: inout DrawerDrag, translation: CGSize) {
        if !state.locked {
            guard isHorizontal(translation) else { return }
            state.locked = true
            state.origin = translation.width
        }
        state.offset = translation.width - state.origin
    }

    /// Drawer position (0 = closed … width = open) for a resting state plus a live drag.
    static func position(isOpen: Bool, width: CGFloat, drag: CGFloat) -> CGFloat {
        min(max((isOpen ? width : 0) + drag, 0), width)
    }

    /// Where the drawer should settle when the finger lifts: `nil` if this was not a horizontal drag (leave as is).
    /// Uses the projected end position (so a quick flick works) against the halfway point.
    static func settlesOpen(isOpen: Bool, width: CGFloat, translation: CGSize, predictedEnd: CGSize) -> Bool? {
        guard abs(translation.width) > lockDistance, abs(translation.width) > abs(translation.height) else { return nil }
        let base: CGFloat = isOpen ? width : 0
        return min(max(base + predictedEnd.width, 0), width) > width / 2
    }
}

/// Push-style side drawer: the content slides aside while the drawer parallax-slides in beneath it.
/// Interactive — follows the finger 1:1, settles with a spring using the drag velocity. A rightward swipe from
/// anywhere opens it (when `swipeEnabled`); tapping or dragging the dimmed content closes it.
/// The dim layer deliberately ignores the safe areas so it covers the whole screen.
///
/// Robustness notes:
/// - the drag state is a `@GestureState`, so it always resets — even if the system cancels the gesture — and its reset
///   uses the same spring as the settle, so lifting the finger never snaps the drawer back first;
/// - the drawer starts following from the finger position at the moment the swipe is recognised (no leap);
/// - the dim layer is never removed from the hierarchy mid-drag (that cancelled the closing gesture and left
///   `isOpen` stuck), it only stops hit-testing when closed.
struct DrawerContainer<Drawer: View, Content: View>: View {
    @Binding var isOpen: Bool
    var swipeEnabled = true
    @ViewBuilder var drawer: () -> Drawer
    @ViewBuilder var content: () -> Content

    @GestureState(resetTransaction: Transaction(animation: DrawerContainer.spring)) private var drag = DrawerDrag()

    private static var spring: Animation { .spring(response: 0.38, dampingFraction: 0.86) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width < 600 ? geo.size.width * 0.7 : 380
            let offset = DrawerMath.position(isOpen: isOpen, width: width, drag: drag.offset)
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
        DragGesture(minimumDistance: 6)
            .updating($drag) { value, state, transaction in
                DrawerMath.update(&state, translation: value.translation)
                transaction.animation = nil   // follow the finger immediately, no lag
            }
            .onEnded { value in
                guard let open = DrawerMath.settlesOpen(
                    isOpen: isOpen, width: width, translation: value.translation, predictedEnd: value.predictedEndTranslation
                ) else { return }
                withAnimation(Self.spring) { isOpen = open }
            }
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
