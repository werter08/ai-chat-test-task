import SwiftUI

struct RootView: View {
    @State private var selection: Chat?

    var body: some View {
        NavigationSplitView {
            ChatListView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 400)
        } detail: {
            if let selection {
                ChatView(chat: selection)
                    .id(selection.id)
            } else {
                ContentUnavailableView(
                    "No chat selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Pick a chat or start a new one.")
                )
            }
        }
    }
}
