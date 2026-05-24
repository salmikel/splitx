import Foundation
import Supabase

// MARK: - Client

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://jxcbchqewasrqjatznci.supabase.co")!,
    supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp4Y2JjaHFld2FzcnFqYXR6bmNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2NTI5NDQsImV4cCI6MjA5NTIyODk0NH0.kcn3wqTnwkppl7XiVQ9Lli5NnDncXUjYMAwQHESwj9E"
)

// MARK: - SupabaseService

@MainActor
final class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    private init() {}

    // MARK: Profile

    func fetchProfile(id: UUID) async throws -> Profile {
        try await supabase
            .from("profiles")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }

    func updateProfile(id: UUID, displayName: String?) async throws {
        try await supabase
            .from("profiles")
            .update(["display_name": displayName as Any])
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: Groups

    func fetchGroups(userId: UUID) async throws -> [SplitGroup] {
        let members: [GroupMember] = try await supabase
            .from("group_members")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value

        let ids = members.map { $0.groupId.uuidString }
        guard !ids.isEmpty else { return [] }

        return try await supabase
            .from("groups")
            .select()
            .in("id", values: ids)
            .order("created_at")
            .execute()
            .value
    }

    func createGroup(name: String, userId: UUID) async throws -> SplitGroup {
        let group: SplitGroup = try await supabase
            .from("groups")
            .insert(["name": name, "created_by": userId.uuidString])
            .select()
            .single()
            .execute()
            .value

        try await supabase
            .from("group_members")
            .insert(["group_id": group.id.uuidString, "user_id": userId.uuidString])
            .execute()

        return group
    }

    // MARK: Members

    func fetchMembers(groupId: UUID) async throws -> [Profile] {
        struct MemberRow: Decodable {
            let userId: UUID
            enum CodingKeys: String, CodingKey { case userId = "user_id" }
        }
        let rows: [MemberRow] = try await supabase
            .from("group_members")
            .select("user_id")
            .eq("group_id", value: groupId.uuidString)
            .execute()
            .value

        let ids = rows.map { $0.userId.uuidString }
        guard !ids.isEmpty else { return [] }

        return try await supabase
            .from("profiles")
            .select()
            .in("id", values: ids)
            .execute()
            .value
    }

    // MARK: Invitations

    func fetchPendingInvitations(groupId: UUID) async throws -> [Invitation] {
        try await supabase
            .from("invitations")
            .select()
            .eq("group_id", value: groupId.uuidString)
            .eq("status", value: "pending")
            .execute()
            .value
    }

    func sendInvitation(groupId: UUID, invitedBy: UUID, email: String) async throws {
        try await supabase
            .from("invitations")
            .insert([
                "group_id": groupId.uuidString,
                "invited_by": invitedBy.uuidString,
                "email": email
            ])
            .execute()
    }

    // MARK: Transactions

    func fetchTransactions(groupId: UUID) async throws -> [SplitTransaction] {
        try await supabase
            .from("transactions")
            .select("*, splits:transaction_splits(*)")
            .eq("group_id", value: groupId.uuidString)
            .order("date", ascending: false)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func createTransaction(
        groupId: UUID,
        description: String,
        amount: Double,
        paidBy: UUID,
        type: TransactionType,
        date: String,
        splits: [(userId: UUID, percentage: Double, amount: Double)]
    ) async throws {
        struct TxInsert: Encodable {
            let group_id: String
            let description: String
            let amount: Double
            let paid_by: String
            let type: String
            let date: String
        }
        struct SplitInsert: Encodable {
            let transaction_id: String
            let user_id: String
            let percentage: Double
            let amount: Double
        }

        let tx: SplitTransaction = try await supabase
            .from("transactions")
            .insert(TxInsert(
                group_id: groupId.uuidString,
                description: description,
                amount: amount,
                paid_by: paidBy.uuidString,
                type: type.rawValue,
                date: date
            ))
            .select()
            .single()
            .execute()
            .value

        let splitRows = splits.map { s in
            SplitInsert(
                transaction_id: tx.id.uuidString,
                user_id: s.userId.uuidString,
                percentage: s.percentage,
                amount: s.amount
            )
        }
        if !splitRows.isEmpty {
            try await supabase.from("transaction_splits").insert(splitRows).execute()
        }
    }

    func updateTransaction(
        id: UUID,
        description: String,
        amount: Double,
        paidBy: UUID,
        type: TransactionType,
        date: String,
        splits: [(userId: UUID, percentage: Double, amount: Double)]
    ) async throws {
        struct TxUpdate: Encodable {
            let description: String
            let amount: Double
            let paid_by: String
            let type: String
            let date: String
        }
        struct SplitInsert: Encodable {
            let transaction_id: String
            let user_id: String
            let percentage: Double
            let amount: Double
        }

        try await supabase
            .from("transactions")
            .update(TxUpdate(description: description, amount: amount, paid_by: paidBy.uuidString, type: type.rawValue, date: date))
            .eq("id", value: id.uuidString)
            .execute()

        try await supabase.from("transaction_splits").delete().eq("transaction_id", value: id.uuidString).execute()

        let splitRows = splits.map { s in
            SplitInsert(transaction_id: id.uuidString, user_id: s.userId.uuidString, percentage: s.percentage, amount: s.amount)
        }
        if !splitRows.isEmpty {
            try await supabase.from("transaction_splits").insert(splitRows).execute()
        }
    }

    func deleteTransaction(id: UUID) async throws {
        try await supabase.from("transactions").delete().eq("id", value: id.uuidString).execute()
    }
}
