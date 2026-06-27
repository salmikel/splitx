import SwiftUI

@main
struct SplitXApp: App {
    @StateObject private var auth = AuthViewModel()
    @StateObject private var appVM = AppViewModel()
    @StateObject private var networkMonitor = NetworkMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(appVM)
                .environmentObject(networkMonitor)
                .onOpenURL { url in
                    Task { await auth.handleDeepLink(url) }
                }
                .task {
                    await NotificationManager.shared.requestAuthorization()
                }
                .onAppear {
                    // Wire the ViewModel to the network monitor once at startup.
                    // This Combine subscription auto-syncs pending transactions
                    // whenever the device reconnects, regardless of view state.
                    appVM.observeNetwork(networkMonitor)
                }
        }
    }
}
