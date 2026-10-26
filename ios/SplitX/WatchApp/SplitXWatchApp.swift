import SwiftUI

@main
struct SplitXWatchApp: App {
    @StateObject private var connectivity = WatchConnectivityManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(connectivity)
        }
        .onChange(of: scenePhase) { _, phase in
            // Retry anything the iPhone hasn't confirmed yet.
            if phase == .active { connectivity.resendUnconfirmed() }
        }
    }
}
