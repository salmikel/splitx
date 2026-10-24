import SwiftUI

@main
struct SplitXWatchApp: App {
    @StateObject private var connectivity = WatchConnectivityManager()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(connectivity)
        }
    }
}
