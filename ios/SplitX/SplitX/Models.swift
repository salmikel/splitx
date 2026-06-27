import Foundation

struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    let email: String
    var displayName: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email
        case displayName = "display_name"
        case createdAt = "created_at"
    }

    var name: String { displayName ?? email.components(separatedBy: "@").first ?? email }
    var initial: String { String((name.first ?? "?").uppercased()) }
}

struct SplitGroup: Codable, Identifiable {
    let id: UUID
    let name: String
    let createdBy: UUID?
    let createdAt: Date
    var defaultPaidBy: UUID?
    var defaultSplits: [String: Double]

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdBy = "created_by"
        case createdAt = "created_at"
        case defaultPaidBy = "default_paid_by"
        case defaultSplits = "default_splits"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdBy = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        defaultPaidBy = try c.decodeIfPresent(UUID.self, forKey: .defaultPaidBy)
        defaultSplits = (try? c.decodeIfPresent([String: Double].self, forKey: .defaultSplits)) ?? [:]
    }
}

struct GroupMember: Codable, Identifiable {
    let id: UUID
    let groupId: UUID
    let userId: UUID
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groupId = "group_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
    }
}

enum TransactionType: String, Codable {
    case expense, payment
}

struct SplitTransaction: Codable, Identifiable {
    let id: UUID
    let groupId: UUID
    let description: String
    let amount: Double
    let paidBy: UUID?
    let type: TransactionType
    let date: String
    let createdAt: Date
    let updatedAt: Date
    var splits: [TxSplit]?

    enum CodingKeys: String, CodingKey {
        case id
        case groupId = "group_id"
        case description, amount
        case paidBy = "paid_by"
        case type, date
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case splits
    }
}

struct TxSplit: Codable, Identifiable {
    let id: UUID
    let transactionId: UUID
    let userId: UUID
    let percentage: Double
    let amount: Double

    enum CodingKeys: String, CodingKey {
        case id
        case transactionId = "transaction_id"
        case userId = "user_id"
        case percentage, amount
    }
}

struct Invitation: Codable, Identifiable {
    let id: UUID
    let groupId: UUID
    let invitedBy: UUID?
    let email: String
    let token: String
    let status: String
    let createdAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groupId = "group_id"
        case invitedBy = "invited_by"
        case email, token, status
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

struct Balance: Identifiable {
    var id: String { "\(fromUserId)-\(toUserId)" }
    let fromUserId: UUID
    let toUserId: UUID
    let fromProfile: Profile
    let toProfile: Profile
    let amount: Double
}

// MARK: - Offline Pending Transaction

/// A transaction captured while the device was offline.
/// Persisted in UserDefaults and synced to Supabase on reconnect.
struct PendingTransaction: Codable, Identifiable {
    struct SplitEntry: Codable {
        let userId: UUID
        let percentage: Double
        let amount: Double
    }

    let id: UUID            // Local-only UUID, replaced by server ID after sync
    let groupId: UUID
    let description: String
    let amount: Double
    let paidBy: UUID
    let type: TransactionType
    let date: String        // "yyyy-MM-dd"
    let splits: [SplitEntry]
    let queuedAt: Date
}
