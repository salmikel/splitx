import SwiftUI

@main
struct SplitXApp: App {
    @StateObject private var auth = AuthViewModel()
    @StateObject private var appVM: AppViewModel
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var subscriptions: SubscriptionManager
    @StateObject private var adManager = AdManager()
    @StateObject private var watchSettings: WatchSettingsStore

    init() {
        // Built here so the Apple Watch bridge (Premium) can use them at
        // launch: when the Watch wakes the app in the background to save an
        // expense, no window appears, so onAppear never runs.
        let appVM = AppViewModel()
        let subscriptions = SubscriptionManager()
        let watchSettings = WatchSettingsStore()
        _appVM = StateObject(wrappedValue: appVM)
        _subscriptions = StateObject(wrappedValue: subscriptions)
        _watchSettings = StateObject(wrappedValue: watchSettings)

        let watch = WatchSessionManager.shared
        watch.setExpenseHandler { expense, notifyOnFailure in
            await appVM.saveWatchExpense(expense, settings: watchSettings,
                                         subscriptions: subscriptions,
                                         notifyOnFailure: notifyOnFailure)
        }
        watch.activate()
    }

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

                    // Keep the Apple Watch's configuration current.
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
