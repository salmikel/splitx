import Foundation
import WatchConnectivity

/// iPhone side of the Apple Watch bridge (Premium feature).
///
/// Pushes the Watch's configuration (Premium state + target group) with
/// `updateApplicationContext`, and receives expenses captured on the Watch via
/// `transferUserInfo`. Saving them is delegated to the handler installed with
/// `setExpenseHandler`, so all Supabase / premium logic stays in AppViewModel.
@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    private var expenseHandler: ((WatchExpense) -> Void)?
    /// Expenses delivered before a handler was installed (a queued transfer can
    /// arrive as soon as the session activates, before the UI is up).
    private var undelivered: [WatchExpense] = []
    private var latestConfig: WatchConfig?

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    override private init() { super.init() }

    /// Activates the session. Call once at launch.
    func activate() {
        guard let session, session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    func setExpenseHandler(_ handler: @escaping (WatchExpense) -> Void) {
        expenseHandler = handler
        let queued = undelivered
        undelivered = []
        queued.forEach(handler)
    }

    /// Sends the latest configuration to the Watch. Safe to call often; it is
    /// remembered and re-sent once the session is activated / a Watch is paired.
    func syncConfig(_ config: WatchConfig) {
        guard config != latestConfig else { return }
        latestConfig = config
        pushConfig()
    }

    private func pushConfig() {
        guard let session,
              session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled,
              let config = latestConfig,
              let payload = WatchPayload.encode(config, key: WatchPayloadKey.config)
        else { return }
        try? session.updateApplicationContext(payload)
    }

    private func receive(_ expense: WatchExpense) {
        if let expenseHandler {
            expenseHandler(expense)
        } else {
            undelivered.append(expense)
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.pushConfig() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Called when the user switches to a different Watch; reactivate so the
    /// new one gets the configuration.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.pushConfig() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        // Only the Sendable Data crosses to the main actor; decode there.
        guard let data = userInfo[WatchPayloadKey.expense] as? Data else { return }
        Task { @MainActor in
            guard let expense = WatchPayload.decode(WatchExpense.self, key: WatchPayloadKey.expense,
                                                    from: [WatchPayloadKey.expense: data]) else { return }
            self.receive(expense)
        }
    }
}
