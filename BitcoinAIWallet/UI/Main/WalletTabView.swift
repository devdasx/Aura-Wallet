import SwiftUI

// MARK: - WalletTabView
// Minimal tab structure for the chat-first wallet.
//
// Since this is a chat-first app, there is no traditional tab bar.
// The primary interface is MainWalletView (chat + balance header).
// Settings is accessed via the gear icon in the balance header,
// not through a separate tab.
//
// This view exists as the entry point that can later support
// additional navigation patterns (e.g., sheet-based settings,
// full-screen overlays) without changing the app root.

struct WalletTabView: View {
    @EnvironmentObject var appRouter: AppRouter

    @State private var selectedTab: WalletTab = .chat
    @State private var isShowingSettings: Bool = false

    // MARK: - Tab Definition

    /// Available tabs in the wallet interface.
    /// Currently only `.chat` is used; settings is accessed via the header gear icon.
    enum WalletTab: String, CaseIterable, Identifiable {
        case chat
        case settings

        var id: String { rawValue }
    }

    // MARK: - Body

    var body: some View {
        MainWalletView()
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
                    .environmentObject(appRouter)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .navigateToSettings)
            ) { _ in
                isShowingSettings = true
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .navigateToSend)
            ) { notification in
                // Deep link: bitcoinai://send or bitcoin:<address>
                // Inject a "send" command into the chat to trigger the send flow.
                if let url = notification.userInfo?["url"] as? URL {
                    let address = (url.host ?? url.path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    if !address.isEmpty {
                        NotificationCenter.default.post(
                            name: .chatInjectCommand,
                            object: nil,
                            userInfo: ["command": "send \(address)"]
                        )
                    } else {
                        NotificationCenter.default.post(
                            name: .chatInjectCommand,
                            object: nil,
                            userInfo: ["command": "send"]
                        )
                    }
                } else {
                    NotificationCenter.default.post(
                        name: .chatInjectCommand,
                        object: nil,
                        userInfo: ["command": "send"]
                    )
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .navigateToReceive)
            ) { _ in
                NotificationCenter.default.post(
                    name: .chatInjectCommand,
                    object: nil,
                    userInfo: ["command": "receive"]
                )
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .bitcoinURIReceived)
            ) { notification in
                // Handle bitcoin: URI by injecting a send command with the address
                if let url = notification.userInfo?["url"] as? URL {
                    let address = url.path.isEmpty ? (url.host ?? "") : url.path
                    let cleanAddress = address.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    if !cleanAddress.isEmpty {
                        NotificationCenter.default.post(
                            name: .chatInjectCommand,
                            object: nil,
                            userInfo: ["command": "send \(cleanAddress)"]
                        )
                    }
                }
            }
    }
}

// MARK: - Preview

#if DEBUG
struct WalletTabView_Previews: PreviewProvider {
    static var previews: some View {
        WalletTabView()
            .environmentObject(AppRouter())
            .preferredColorScheme(.dark)
    }
}
#endif
