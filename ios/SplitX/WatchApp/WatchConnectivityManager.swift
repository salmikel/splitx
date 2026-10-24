import Foundation
import WatchConnectivity

/// Watch side of the iPhone bridge. Receives the configuration (Premium state,
/// target group, currency) from the iPhone and hands captured expenses to it.
/// All saving, splitting, and Premium enforcement happens on the iPhone.
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    @Published private(set) var config: WatchConfig = .empty
    /// False until the iPhone has sent a configuration at least once.
    @Published private(set) var hasReceivedConfig = false

    /// Expenses captured before the session finished activating.
    private var unsent: [WatchExpense] = []
    private static let cacheKey = "splitx.watch.config.v1"

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    override init() {
        super.init()
        // Show the last known configuration immediately, even if the iPhone
        // isn't reachable right now.
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey) {
            apply(data, persist: false)
        }
        session?.delegate = self
        session?.activate()
    }

    /// Whether the iPhone is reachable right now (otherwise transfers queue).
    var isPhoneReachable: Bool { session?.isReachable ?? false }

    /// Queues the expense for delivery to the iPhone. `transferUserInfo`
    /// survives the iPhone being out of range or the app not running.
    func send(_ expense: WatchExpense) {
        guard let session, session.activationState == .activated else {
            unsent.append(expense)
            return
        }
        guard let payload = WatchPayload.encode(expense, key: WatchPayloadKey.expense) else { return }
        session.transferUserInfo(payload)
    }

    private func flushUnsent() {
        let queued = unsent
        unsent = []
        queued.forEach(send)
    }

    private func apply(_ data: Data, persist: Bool) {
        guard let decoded = WatchPayload.decode(WatchConfig.self, key: WatchPayloadKey.config,
                                                from: [WatchPayloadKey.config: data]) else { return }
        config = decoded
        hasReceivedConfig = true
        if persist { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        // The latest context may have arrived while the app wasn't running.
        let data = session.receivedApplicationContext[WatchPayloadKey.config] as? Data
        Task { @MainActor in
            if let data { self.apply(data, persist: true) }
            self.flushUnsent()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchPayloadKey.config] as? Data else { return }
        Task { @MainActor in self.apply(data, persist: true) }
    }
}
