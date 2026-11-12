import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Push-style side drawer: the content slides aside while the drawer parallax-slides in beneath it.
/// Interactive — follows the finger, settles with a spring using the drag velocity, and can be opened by an
/// edge swipe (when `edgeSwipeEnabled`) and closed by tapping or dragging the dimmed content.
/// The dim layer deliberately ignores the safe areas so it covers the whole screen.
struct DrawerContainer<Drawer: View, Content: View>: View {
    @Binding var isOpen: Bool
    var edgeSwipeEnabled = true
    @ViewBuilder var drawer: () -> Drawer
    @ViewBuilder var content: () -> Content

    @State private var drag: CGFloat = 0

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
                    .simultaneousGesture(dragGesture(width: width))

                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { Rectangle().fill(.background).ignoresSafeArea() }
                    .shadow(color: .black.opacity(0.28 * progress), radius: 16, x: -3)
                    .offset(x: offset)

                if progress > 0.001 {
                    Color.black.opacity(0.22 * progress)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .offset(x: offset)
                        .onTapGesture { setOpen(false) }
                        .gesture(dragGesture(width: width))
                        .accessibilityLabel("Close menu")
                        .accessibilityAddTraits(.isButton)
                }

                if !isOpen && edgeSwipeEnabled {
                    Color.clear
                        .frame(width: 22)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(width: width))
                }
            }
        }
        .onChange(of: isOpen) { _, open in if open { Self.dismissKeyboard() } }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Ignore mostly-vertical drags (list/scroll gestures).
                guard drag != 0 || abs(value.translation.width) > abs(value.translation.height) else { return }
                drag = value.translation.width
            }
            .onEnded { value in
                let base: CGFloat = isOpen ? width : 0
                let projected = base + value.predictedEndTranslation.width
                let shouldOpen = abs(drag) > 0 ? projected > width / 2 : isOpen
                withAnimation(Self.spring) {
                    isOpen = shouldOpen
                    drag = 0
                }
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
