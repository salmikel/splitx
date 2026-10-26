import Foundation
import UIKit
import WatchConnectivity

/// iPhone side of the Apple Watch bridge (Premium feature).
///
/// Pushes the Watch's configuration (Premium state + target group) with
/// `updateApplicationContext`. Expenses arrive two ways: `sendMessage`, which
/// wakes this app in the background and waits for a `WatchSaveReply`, and
/// `transferUserInfo`, the fallback the system delivers whenever this app next
/// runs. The same expense can come both ways, so each id is saved only once.
/// Saving itself is delegated to the handler from `setExpenseHandler`, so all
/// Supabase / premium logic stays in AppViewModel.
@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    /// Saves one expense. `notifyOnFailure` is true when the Watch can't
    /// receive the reply (a `transferUserInfo` delivery).
    typealias ExpenseHandler = (_ expense: WatchExpense, _ notifyOnFailure: Bool) async -> WatchSaveReply

    private var expenseHandler: ExpenseHandler?
    private var latestConfig: WatchConfig?

    /// Outcomes of recently handled expenses, so a second delivery of the same
    /// expense is answered without saving it again. Persisted because the two
    /// deliveries can arrive in different launches.
    private var outcomes: [WatchSaveReply] = []
    private var inFlight: [UUID: Task<WatchSaveReply, Never>] = [:]
    private static let outcomesKey = "splitx.watch.outcomes.v1"
    private static let outcomesLimit = 200

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    override private init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.outcomesKey),
           let saved = try? JSONDecoder().decode([WatchSaveReply].self, from: data) {
            outcomes = saved
        }
    }

    /// Install before `activate()`: deliveries can arrive as soon as the
    /// session is active.
    func setExpenseHandler(_ handler: @escaping ExpenseHandler) {
        expenseHandler = handler
    }

    /// Activates the session. Call once at launch (including background
    /// launches, where no window appears).
    func activate() {
        guard let session, session.delegate == nil else { return }
        session.delegate = self
        session.activate()
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

    // MARK: - Receiving expenses

    private func receive(_ data: Data, viaMessage: Bool) async -> WatchSaveReply? {
        guard let expense = WatchPayload.decode(WatchExpense.self, key: WatchPayloadKey.expense,
                                                from: [WatchPayloadKey.expense: data]) else { return nil }
        if let done = outcomes.first(where: { $0.expenseId == expense.id }) { return done }
        if let running = inFlight[expense.id] { return await running.value }
        guard let expenseHandler else { return nil }

        // Keep running long enough to finish the save when the Watch woke us
        // in the background.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save Watch expense")
        defer { UIApplication.shared.endBackgroundTask(backgroundTask) }

        let task = Task { await expenseHandler(expense, !viaMessage) }
        inFlight[expense.id] = task
        let reply = await task.value
        inFlight[expense.id] = nil
        record(reply)
        return reply
    }

    private func record(_ reply: WatchSaveReply) {
        outcomes.append(reply)
        if outcomes.count > Self.outcomesLimit {
            outcomes.removeFirst(outcomes.count - Self.outcomesLimit)
        }
        let data = try? JSONEncoder().encode(outcomes)
        UserDefaults.standard.set(data, forKey: Self.outcomesKey)
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

    /// The Watch's primary delivery: it woke this app and waits for the reply.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        // Only the Sendable Data crosses to the main actor; decode there.
        guard let data = message[WatchPayloadKey.expense] as? Data else {
            replyHandler([:])
            return
        }
        Task { @MainActor in
            let reply = await self.receive(data, viaMessage: true)
            replyHandler(reply.flatMap { WatchPayload.encode($0, key: WatchPayloadKey.reply) } ?? [:])
        }
    }

    /// The queued fallback, delivered whenever this app next runs.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[WatchPayloadKey.expense] as? Data else { return }
        Task { @MainActor in _ = await self.receive(data, viaMessage: false) }
    }
}
