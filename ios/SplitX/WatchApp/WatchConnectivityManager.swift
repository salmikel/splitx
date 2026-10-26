import Foundation
import WatchConnectivity

/// Watch side of the iPhone bridge. Receives the configuration (Premium state,
/// target group, currency) from the iPhone and hands captured expenses to it.
/// All saving, splitting, and Premium enforcement happens on the iPhone.
///
/// Each expense is queued with `transferUserInfo` (the outbox: it survives
/// relaunches and is delivered whenever the iPhone app next runs) and also
/// sent with `sendMessage`, which wakes the iPhone app in the background so it
/// saves right away. When the iPhone confirms, the queued copy is cancelled;
/// unconfirmed ones are re-sent whenever the iPhone becomes reachable again.
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    @Published private(set) var config: WatchConfig = .empty
    /// False until the iPhone has sent a configuration at least once.
    @Published private(set) var hasReceivedConfig = false
    /// The iPhone's answer for each expense it has confirmed this launch.
    @Published private(set) var replies: [UUID: WatchSaveReply] = [:]

    /// Expenses captured before the session finished activating.
    private var unsent: [WatchExpense] = []
    /// Expenses with a `sendMessage` currently waiting for its reply.
    private var delivering: Set<UUID> = []
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

    /// Whether the iPhone is reachable right now (otherwise sends wait in the outbox).
    var isPhoneReachable: Bool { session?.isReachable ?? false }

    func send(_ expense: WatchExpense) {
        guard let session, session.activationState == .activated else {
            unsent.append(expense)
            return
        }
        guard let payload = WatchPayload.encode(expense, key: WatchPayloadKey.expense) else { return }
        session.transferUserInfo(payload)
        deliver(expense.id, payload: payload)
    }

    /// Re-sends every expense the iPhone hasn't confirmed yet, e.g. ones logged
    /// while it was out of range. Called on activation, when the iPhone becomes
    /// reachable, and when the app comes to the foreground.
    func resendUnconfirmed() {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        for transfer in session.outstandingUserInfoTransfers {
            guard let id = Self.expenseId(in: transfer.userInfo) else { continue }
            deliver(id, payload: transfer.userInfo)
        }
    }

    /// Wakes the iPhone app and waits for it to save the expense.
    private func deliver(_ id: UUID, payload: [String: Any]) {
        guard let session, session.isReachable, !delivering.contains(id) else { return }
        delivering.insert(id)
        session.sendMessage(payload, replyHandler: { response in
            let data = response[WatchPayloadKey.reply] as? Data
            Task { @MainActor in self.handleReply(for: id, data: data) }
        }, errorHandler: { _ in
            // Still in the outbox; retried when the iPhone is reachable again.
            Task { @MainActor in self.delivering.remove(id) }
        })
    }

    private func handleReply(for id: UUID, data: Data?) {
        delivering.remove(id)
        // An empty reply means the iPhone couldn't take it yet; keep it queued.
        guard let data,
              let reply = WatchPayload.decode(WatchSaveReply.self, key: WatchPayloadKey.reply,
                                              from: [WatchPayloadKey.reply: data]) else { return }
        replies[id] = reply
        // Confirmed: drop the queued copy so it isn't delivered again.
        for transfer in session?.outstandingUserInfoTransfers ?? []
        where Self.expenseId(in: transfer.userInfo) == id {
            transfer.cancel()
        }
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

    private static func expenseId(in userInfo: [String: Any]) -> UUID? {
        WatchPayload.decode(WatchExpense.self, key: WatchPayloadKey.expense, from: userInfo)?.id
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
            self.resendUnconfirmed()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchPayloadKey.config] as? Data else { return }
        Task { @MainActor in self.apply(data, persist: true) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.resendUnconfirmed() }
    }
}
