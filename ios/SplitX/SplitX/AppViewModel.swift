import Foundation
import Supabase

@MainActor
final class AppViewModel: ObservableObject {
    @Published var currentUser: Profile?
    @Published var groups: [SplitGroup] = []
    @Published var selectedGroup: SplitGroup?
    @Published var members: [Profile] = []
    @Published var transactions: [SplitTransaction] = []
    @Published var balances: [Balance] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = SupabaseService.shared

    func load() async {
        guard let user = try? await supabase.auth.user() else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            currentUser = try await service.fetchProfile(id: user.id)
            groups = try await service.fetchGroups(userId: user.id)
            if selectedGroup == nil { selectedGroup = groups.first }
            if let group = selectedGroup {
                try await loadGroup(group)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadGroup(_ group: SplitGroup) async throws {
        selectedGroup = group
        members = try await service.fetchMembers(groupId: group.id)
        transactions = try await service.fetchTransactions(groupId: group.id)
        balances = computeBalances()
    }

    func refresh() async {
        guard let group = selectedGroup else { return }
        do { try await loadGroup(group) } catch { errorMessage = error.localizedDescription }
    }

    func selectGroup(_ group: SplitGroup) async {
        do { try await loadGroup(group) } catch { errorMessage = error.localizedDescription }
    }

    // MARK: Balance computation

    private func computeBalances() -> [Balance] {
        var net = [UUID: [UUID: Double]]()
        for m in members {
            net[m.id] = [:]
            for m2 in members where m.id != m2.id { net[m.id]![m2.id] = 0 }
        }

        for tx in transactions {
            guard let splits = tx.splits, let paidBy = tx.paidBy else { continue }
            for split in splits {
                guard split.userId != paidBy else { continue }
                net[split.userId]?[paidBy] = (net[split.userId]?[paidBy] ?? 0) + split.amount
                net[paidBy]?[split.userId] = (net[paidBy]?[split.userId] ?? 0) - split.amount
            }
        }

        var result = [Balance]()
        let profileMap = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        var seen = Set<String>()

        for a in members {
            for b in members where a.id != b.id {
                let key = [a.id.uuidString, b.id.uuidString].sorted().joined(separator: ":")
                guard !seen.contains(key) else { continue }
                seen.insert(key)

                let aOwesB = net[a.id]?[b.id] ?? 0
                let bOwesA = net[b.id]?[a.id] ?? 0
                let netAmt = aOwesB - bOwesA
                guard abs(netAmt) >= 0.01 else { continue }

                let fromId = netAmt > 0 ? a.id : b.id
                let toId = netAmt > 0 ? b.id : a.id
                guard let from = profileMap[fromId], let to = profileMap[toId] else { continue }
                result.append(Balance(fromUserId: fromId, toUserId: toId, fromProfile: from, toProfile: to, amount: abs(netAmt)))
            }
        }
        return result
    }
}
