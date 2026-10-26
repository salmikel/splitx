import Foundation

// Payloads exchanged between the iPhone app and the Apple Watch app over
// WatchConnectivity. This file belongs to BOTH the SplitX (iOS) and the
// SplitX Watch App targets, so keep it Foundation-only.

/// iPhone → Watch: everything the Watch needs to run its capture flow.
/// Sent with `updateApplicationContext`, so only the latest value matters.
nonisolated struct WatchConfig: Codable, Equatable {
    var isPremium: Bool
    var groupId: UUID?
    var groupName: String
    var currencyCode: String
    var currencySymbol: String

    /// A group has been chosen for the Watch in iPhone Settings.
    var isConfigured: Bool { groupId != nil }

    static let empty = WatchConfig(
        isPremium: false, groupId: nil, groupName: "",
        currencyCode: "USD", currencySymbol: "$"
    )
}

/// Watch → iPhone: one expense captured on the Watch. Sent with `sendMessage`
/// (wakes the iPhone app in the background) and also queued with
/// `transferUserInfo` as a fallback, so the iPhone de-duplicates by `id`.
/// The iPhone applies the paid-by and split allocation configured in Settings.
nonisolated struct WatchExpense: Codable, Identifiable {
    let id: UUID
    let groupId: UUID
    let description: String
    let amount: Double
    let createdAt: Date
}

nonisolated enum WatchSaveStatus: String, Codable {
    case saved      // stored in Supabase
    case queued     // kept on the iPhone; uploads when it's back online
    case rejected   // not saved, see `message`
}

/// iPhone → Watch: the outcome of saving one `WatchExpense`, sent as the reply
/// to `sendMessage`. Once the Watch has it, the expense is never resent.
nonisolated struct WatchSaveReply: Codable {
    let expenseId: UUID
    let status: WatchSaveStatus
    let message: String?
}

nonisolated enum WatchPayloadKey {
    static let config  = "config"
    static let expense = "expense"
    static let reply   = "reply"
}

/// Wraps a Codable value as JSON `Data` inside a WatchConnectivity dictionary
/// (dictionary values must be property-list types).
nonisolated enum WatchPayload {
    static func encode<T: Encodable>(_ value: T, key: String) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return [key: data]
    }

    static func decode<T: Decodable>(_ type: T.Type, key: String, from dictionary: [String: Any]) -> T? {
        guard let data = dictionary[key] as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
