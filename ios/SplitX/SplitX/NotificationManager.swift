import Foundation
import UserNotifications
import Supabase

// MARK: - AnyJSON helpers

/// Extends AnyJSON so numeric amounts stored as integer JSON values are
/// also readable as Double (e.g. 100 instead of 100.0).
private extension AnyJSON {
    var numericValue: Double? {
        doubleValue ?? intValue.map(Double.init)
    }
}

// MARK: - NotificationManager

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    private var realtimeTask: Task<Void, Never>?
    private var realtimeChannel: RealtimeChannelV2?

    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Realtime subscriptions

    /// Call whenever the signed-in user or their group list changes.
    func startListening(userId: UUID, userEmail: String, groups: [SplitGroup]) {
        stopListening()
        guard !groups.isEmpty else { return }

        let email = userEmail.lowercased()
        let groupIdSet = Set(groups.map { $0.id.uuidString.lowercased() })
        let currencyByGroup = Dictionary(
            uniqueKeysWithValues: groups.map { ($0.id.uuidString.lowercased(), $0.currency) }
        )
        let userIdStr = userId.uuidString.lowercased()

        realtimeTask = Task {
            // Unique topic per subscription. `channel(_:)` caches by topic, so
            // reusing a stable topic can return an already-subscribed channel —
            // and adding postgres_changes after `subscribe()` both warns and
            // silently fails to register. The channel is removed in stopListening.
            let channel = supabase.channel("splitx-notifications-\(userIdStr)-\(UUID().uuidString)")
            self.realtimeChannel = channel

            let txStream     = channel.postgresChange(InsertAction.self, schema: "public", table: "transactions")
            let inviteStream = channel.postgresChange(InsertAction.self, schema: "public", table: "invitations")

            try? await channel.subscribeWithError()

            await withTaskGroup(of: Void.self) { group in
                // New transactions by other group members
                group.addTask {
                    for await change in txStream {
                        guard !Task.isCancelled else { return }

                        let record = change.record
                        guard
                            let gid     = record["group_id"]?.stringValue,
                            groupIdSet.contains(gid.lowercased()),
                            let paidBy  = record["paid_by"]?.stringValue,
                            paidBy.lowercased() != userIdStr
                        else { continue }

                        let desc   = record["description"]?.stringValue ?? "New transaction"
                        let amount = record["amount"]?.numericValue ?? 0
                        let code   = currencyByGroup[gid.lowercased()] ?? "USD"
                        let body   = "\(desc) – \(amount.formatted(.currency(code: code)))"
                        await NotificationManager.shared.fire(title: "New Transaction", body: body)
                    }
                }

                // New invitations addressed to this user
                group.addTask {
                    for await change in inviteStream {
                        guard !Task.isCancelled else { return }

                        guard
                            let invEmail = change.record["email"]?.stringValue,
                            invEmail.lowercased() == email
                        else { continue }

                        await NotificationManager.shared.fire(
                            title: "You've been invited!",
                            body: "Someone invited you to join a group in SplitX. Open the app to accept."
                        )
                    }
                }
            }

            // Clean up channel when the task ends or is cancelled
            await channel.unsubscribe()
        }
    }

    func stopListening() {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let channel = realtimeChannel {
            realtimeChannel = nil
            Task { await supabase.removeChannel(channel) }   // drop it from the client's cache
        }
    }

    // MARK: - Fire local notification

    func fire(title: String, body: String) async {
        let content       = UNMutableNotificationContent()
        content.title     = title
        content.body      = body
        content.sound     = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil          // deliver immediately
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Show banner + play sound even when the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
