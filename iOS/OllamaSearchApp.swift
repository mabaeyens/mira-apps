import SwiftUI

@main
struct OllamaSearchApp: App {
    @State private var chatVM = ChatViewModel()
    @State private var serverURL: URL? = {
        UserDefaults.standard.string(forKey: "serverURL")
            .flatMap(URL.init(string:))
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if let url = serverURL {
                    connectedView(serverURL: url)
                } else {
                    ConnectionView { url in
                        serverURL = url
                        APIClient.shared.baseURL = url
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private func connectedView(serverURL: URL) -> some View {
        NavigationSplitView {
            ConversationListView(vm: chatVM)
        } detail: {
            ChatView(
                vm: chatVM,
                attachPicker: AnyView(iOSAttachButton(vm: chatVM))
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        // Disconnect — return to ConnectionView
                        UserDefaults.standard.removeObject(forKey: "serverURL")
                        self.serverURL = nil
                    } label: {
                        Image(systemName: "wifi.slash")
                    }
                }
            }
        }
        .task {
            APIClient.shared.baseURL = serverURL
            await chatVM.loadConversations()
            if chatVM.currentConvId.isEmpty, let first = chatVM.conversations.first {
                chatVM.selectConversation(first.id)
            }
        }
    }
}
