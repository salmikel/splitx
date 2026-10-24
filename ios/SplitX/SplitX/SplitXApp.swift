import SwiftUI

@main
struct SplitXApp: App {
    @StateObject private var auth = AuthViewModel()
    @StateObject private var appVM = AppViewModel()
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var subscriptions = SubscriptionManager()
    @StateObject private var adManager = AdManager()
    @StateObject private var watchSettings = WatchSettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(appVM)
                .environmentObject(networkMonitor)
                .environmentObject(subscriptions)
                .environmentObject(adManager)
                .environmentObject(watchSettings)
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

                    // Initialize the ads SDK and warm up the first interstitial.
                    adManager.start()

                    // Apple Watch bridge (Premium): save expenses captured on
                    // the Watch and keep its configuration current.
                    let watch = WatchSessionManager.shared
                    watch.setExpenseHandler { [appVM, watchSettings, subscriptions] expense in
                        Task {
                            await appVM.saveWatchExpense(expense, settings: watchSettings,
                                                         subscriptions: subscriptions)
                        }
                    }
                    watch.activate()
                    syncWatchConfig()
                }
                .onChange(of: subscriptions.isPremium) { syncWatchConfig() }
                .onChange(of: appVM.groups.map { "\($0.id)|\($0.name)|\($0.currency)" }) {
                    syncWatchConfig()
                }
                .onChange(of: appVM.currentUser?.id) { syncWatchConfig() }
                .onReceive(watchSettings.objectWillChange) {
                    // objectWillChange fires before the new values land.
                    DispatchQueue.main.async { syncWatchConfig() }
                }
        }
    }

    private func syncWatchConfig() {
        WatchSessionManager.shared.syncConfig(
            appVM.watchConfig(settings: watchSettings, isPremium: subscriptions.isPremium)
        )
    }
}
