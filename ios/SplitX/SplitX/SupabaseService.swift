import Foundation
import Supabase

// MARK: - Client

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://jxcbchqewasrqjatznci.supabase.co")!,
    supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp4Y2JjaHFld2FzcnFqYXR6bmNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2NTI5NDQsImV4cCI6MjA5NTIyODk0NH0.kcn3wqTnwkppl7XiVQ9Lli5NnDncXUjYMAwQHESwj9E",
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            emitLocalSessionAsInitialSession: true
        )
    )
)

private let workerBaseURL = "https://splitx.salvador-mikel.workers.dev"

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

    /// Uses a SECURITY DEFINER RPC so that a brand-new Apple-SSO user
    /// (who has no group memberships yet) can still check whether their
    /// email already exists in another account.
    func fetchProfileByEmail(email: String) async throws -> Profile? {
        struct Row: Decodable { let id: UUID; let display_name: String? }
        let rows: [Row] = try await supabase
            .rpc("find_profile_by_email", params: ["lookup_email": email.lowercased()])
            .execute()
            .value
        guard let first = rows.first else { return nil }
        // Return a lightweight Profile-compatible value.
        // We only need the id to confirm the account exists.
        return try await fetchProfile(id: first.id)
    }

    func updateProfile(id: UUID, displayName: String?) async throws {
        struct ProfileUpdate: Encodable {
            let display_name: String?
        }
        try await supabase
            .from("profiles")
            .update(ProfileUpdate(display_name: displayName))
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
        struct GroupInsert: Encodable { let name: String; let created_by: String }
        struct MemberInsert: Encodable { let group_id: String; let user_id: String }

        let group: SplitGroup = try await supabase
            .from("groups")
            .insert(GroupInsert(name: name, created_by: userId.uuidString))
            .select()
            .single()
            .execute()
            .value

        try await supabase
            .from("group_members")
            .insert(MemberInsert(group_id: group.id.uuidString, user_id: userId.uuidString))
            .execute()

        return group
    }

    func fetchGroup(id: UUID) async throws -> SplitGroup {
        try await supabase
            .from("groups")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }

    func updateGroupDefaults(id: UUID, defaultPaidBy: UUID?, defaultSplits: [String: Double]) async throws {
        struct Update: Encodable {
            let default_paid_by: String?
            let default_splits: [String: Double]
        }
        try await supabase
            .from("groups")
            .update(Update(default_paid_by: defaultPaidBy?.uuidString, default_splits: defaultSplits))
            .eq("id", value: id.uuidString)
            .execute()
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

    /// Sends an invite email via the Workers API (which uses Resend) and writes to DB.
    func sendInvitation(groupId: UUID, groupName: String, inviterName: String, email: String) async throws {
        guard let url = URL(string: "\(workerBaseURL)/api/invite") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "email": email,
            "groupId": groupId.uuidString,
            "groupName": groupName,
            "inviterName": inviterName
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let msg = json?["error"] as? String ?? "Failed to send invitation"
            throw NSError(domain: "SplitX", code: 0, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    func deleteInvitation(id: UUID) async throws {
        try await supabase
            .from("invitations")
            .delete()
            .eq("id", value: id.uuidString)
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

    // MARK: Remove Member

    /// Removes a member from a group, reassigning all their paid transactions
    /// and split entries to `replacementUserId`, then updating group defaults.
    func removeMember(
        groupId: UUID,
        removedUserId: UUID,
        replacementUserId: UUID,
        currentDefaultPaidBy: UUID?,
        currentDefaultSplits: [String: Double]
    ) async throws {

        // 1. Reassign paid_by on any transactions they paid
        struct PaidByUpdate: Encodable { let paid_by: String }
        try await supabase
            .from("transactions")
            .update(PaidByUpdate(paid_by: replacementUserId.uuidString))
            .eq("group_id", value: groupId.uuidString)
            .eq("paid_by", value: removedUserId.uuidString)
            .execute()

        // 2. Reassign / merge transaction splits
        struct TxIdRow: Decodable { let id: UUID }
        let txRows: [TxIdRow] = try await supabase
            .from("transactions")
            .select("id")
            .eq("group_id", value: groupId.uuidString)
            .execute()
            .value

        if !txRows.isEmpty {
            let txIds = txRows.map { $0.id.uuidString }

            struct SplitRow: Decodable {
                let id: UUID
                let transactionId: UUID
                let percentage: Double
                let amount: Double
                enum CodingKeys: String, CodingKey {
                    case id
                    case transactionId = "transaction_id"
                    case percentage, amount
                }
            }

            let removedSplits: [SplitRow] = try await supabase
                .from("transaction_splits")
                .select("id,transaction_id,percentage,amount")
                .eq("user_id", value: removedUserId.uuidString)
                .in("transaction_id", values: txIds)
                .execute()
                .value

            if !removedSplits.isEmpty {
                let replacementSplits: [SplitRow] = try await supabase
                    .from("transaction_splits")
                    .select("id,transaction_id,percentage,amount")
                    .eq("user_id", value: replacementUserId.uuidString)
                    .in("transaction_id", values: txIds)
                    .execute()
                    .value

                let repMap = Dictionary(uniqueKeysWithValues: replacementSplits.map { ($0.transactionId, $0) })

                struct SplitMerge: Encodable { let percentage: Double; let amount: Double }
                struct SplitReassign: Encodable { let user_id: String }

                // Partition into conflicts (replacement already has a split for that tx)
                // and clean reassigns (no conflict — just change user_id).
                var nonConflictIds:    [String] = []
                var removedConflictIds: [String] = []
                var conflictPairs: [(removed: SplitRow, replacement: SplitRow)] = []

                for removed in removedSplits {
                    if let existing = repMap[removed.transactionId] {
                        conflictPairs.append((removed, existing))
                        removedConflictIds.append(removed.id.uuidString)
                    } else {
                        nonConflictIds.append(removed.id.uuidString)
                    }
                }

                // One bulk UPDATE for all clean reassigns (replaces N individual calls).
                // Using _ = try? so a transient split failure doesn't block the
                // member deletion that follows — the split content is already
                // correct after the paid_by reassignment above.
                if !nonConflictIds.isEmpty {
                    _ = try? await supabase
                        .from("transaction_splits")
                        .update(SplitReassign(user_id: replacementUserId.uuidString))
                        .in("id", values: nonConflictIds)
                        .execute()
                }

                // For conflicts: update each replacement split's merged totals,
                // then bulk-delete all the now-redundant removed splits at once.
                for pair in conflictPairs {
                    _ = try? await supabase
                        .from("transaction_splits")
                        .update(SplitMerge(
                            percentage: pair.replacement.percentage + pair.removed.percentage,
                            amount:     pair.replacement.amount     + pair.removed.amount
                        ))
                        .eq("id", value: pair.replacement.id.uuidString)
                        .execute()
                }
                if !removedConflictIds.isEmpty {
                    _ = try? await supabase
                        .from("transaction_splits")
                        .delete()
                        .in("id", values: removedConflictIds)
                        .execute()
                }
            }
        }

        // 3. Update group defaults (paid-by and split percentages)
        let newDefaultPaidBy = currentDefaultPaidBy == removedUserId ? replacementUserId : currentDefaultPaidBy
        var newDefaultSplits = currentDefaultSplits
        let removedKey     = removedUserId.uuidString.lowercased()
        let replacementKey = replacementUserId.uuidString.lowercased()
        if let removedPct = newDefaultSplits.removeValue(forKey: removedKey) {
            newDefaultSplits[replacementKey] = (newDefaultSplits[replacementKey] ?? 0) + removedPct
        }

        struct GroupDefaultsUpdate: Encodable {
            let default_paid_by: String?
            let default_splits: [String: Double]
        }
        try await supabase
            .from("groups")
            .update(GroupDefaultsUpdate(
                default_paid_by: newDefaultPaidBy?.uuidString,
                default_splits: newDefaultSplits
            ))
            .eq("id", value: groupId.uuidString)
            .execute()

        // 4. Remove from group_members
        try await supabase
            .from("group_members")
            .delete()
            .eq("group_id", value: groupId.uuidString)
            .eq("user_id", value: removedUserId.uuidString)
            .execute()
    }
}
