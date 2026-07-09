import Foundation
import Combine
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
    @Published var isSyncing = false
    @Published var errorMessage: String?

    /// Transactions captured offline, persisted across launches.
    @Published private(set) var pendingTransactions: [PendingTransaction] = []

    /// Currency code of the currently selected group (falls back to USD).
    var currencyCode: String { selectedGroup?.currency ?? "USD" }

    private let service = SupabaseService.shared
    private static let pendingQueueKey = "splitx.pendingTransactions"
    private static let cacheKey        = "splitx.appState.v1"
    private var cancellables = Set<AnyCancellable>()

    init() {
        loadPendingFromDisk()
        observeAuthSignOut()
    }

    // MARK: - Auth observation

    /// Wipes all local data the moment the user signs out or deletes their
    /// account, so the next account signed in on this device can never see the
    /// previous user's cached profile, groups, members, or balances.
    private func observeAuthSignOut() {
        Task { [weak self] in
            for await (event, _) in supabase.auth.authStateChanges {
                guard let self else { return }
                if event == .signedOut {
                    self.purgeLocalData()
                }
            }
        }
    }

    /// Clears every trace of the current user from memory and disk.
    func purgeLocalData() {
        currentUser = nil
        groups = []
        selectedGroup = nil
        members = []
        transactions = []
        balances = []
        pendingTransactions = []
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingQueueKey)
        NotificationManager.shared.stopListening()
    }

    // MARK: - Network observation

    /// Wire up automatic sync-on-reconnect. Call once from the root view.
    func observeNetwork(_ monitor: NetworkMonitor) {
        monitor.$isOnline
            .removeDuplicates()
            .dropFirst()          // ignore the initial published value
            .filter { $0 }        // only react when coming back online
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refresh() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Load

    func load() async {
        // Read the user from the local keychain session — no network call,
        // so this works offline.
        guard let user = supabase.auth.currentUser else { return }

        // If in-memory state belongs to a different user (e.g. someone signed
        // out and a new account signed in before a purge landed), drop it so we
        // never render the previous user's data.
        if let current = currentUser, current.id != user.id {
            purgeLocalData()
        }

        isLoading = true
        defer { isLoading = false }

        // Hydrate from disk cache first — the UI becomes responsive
        // immediately without waiting for any network round-trip. Only the
        // signed-in user's own cache is loaded (see loadCachedState).
        loadCachedState(for: user.id)

        // Attempt a fresh network fetch. If it fails (offline or flaky
        // connection) we just keep showing the cached data.
        do {
            currentUser = try await service.fetchProfile(id: user.id)
            groups = try await service.fetchGroups(userId: user.id)

            // Preserve the previously selected group if it still exists.
            if let current = selectedGroup {
                selectedGroup = groups.first(where: { $0.id == current.id }) ?? groups.first
            } else {
                selectedGroup = groups.first
            }

            if let group = selectedGroup {
                try await loadGroup(group)
            }

            saveCachedState()

            // Flush any offline-queued transactions so they appear immediately.
            let synced = await syncPendingTransactions()
            if synced, let group = selectedGroup {
                try? await loadGroup(group)
                saveCachedState()
            }

            if let user = currentUser {
                NotificationManager.shared.startListening(
                    userId: user.id,
                    userEmail: user.email,
                    groups: groups
                )
            }
        } catch {
            // If we already populated data from cache, don't surface the
            // network error — the user can work with what they have.
            if groups.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadGroup(_ group: SplitGroup) async throws {
        selectedGroup = group
        members = try await service.fetchMembers(groupId: group.id)
        transactions = try await service.fetchTransactions(groupId: group.id)
        balances = computeBalances()
    }

    func refresh() async {
        guard let current = selectedGroup else { return }
        if !pendingTransactions.isEmpty { isSyncing = true }
        do {
            await syncPendingTransactions()
            let freshGroup = (try? await service.fetchGroup(id: current.id)) ?? current
            try await loadGroup(freshGroup)
            saveCachedState()
        } catch { errorMessage = error.localizedDescription }
        isSyncing = false
    }

    func deleteTransaction(_ tx: SplitTransaction) async {
        // Optimistically remove from local state for instant UI feedback.
        transactions.removeAll { $0.id == tx.id }
        balances = computeBalances()
        do {
            try await service.deleteTransaction(id: tx.id)
            saveCachedState()
        } catch {
            // Rollback: reload from server if the delete failed.
            errorMessage = error.localizedDescription
            if let group = selectedGroup { try? await loadGroup(group) }
        }
    }

    func selectGroup(_ group: SplitGroup) async {
        do {
            try await loadGroup(group)
            saveCachedState()
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Offline Queue

    /// Pending transactions for the currently selected group (for display).
    var pendingForCurrentGroup: [PendingTransaction] {
        guard let id = selectedGroup?.id else { return [] }
        return pendingTransactions.filter { $0.groupId == id }
    }

    func enqueuePending(_ tx: PendingTransaction) {
        pendingTransactions.append(tx)
        persistPendingQueue()
    }

    private func removePending(id: UUID) {
        pendingTransactions.removeAll { $0.id == id }
        persistPendingQueue()
    }

    private func persistPendingQueue() {
        let data = try? JSONEncoder().encode(pendingTransactions)
        UserDefaults.standard.set(data, forKey: Self.pendingQueueKey)
    }

    private func loadPendingFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingQueueKey),
              let decoded = try? JSONDecoder().decode([PendingTransaction].self, from: data) else { return }
        pendingTransactions = decoded
    }

    /// Uploads all queued transactions to Supabase in capture order.
    /// Returns true if at least one was synced successfully.
    @discardableResult
    func syncPendingTransactions() async -> Bool {
        guard !pendingTransactions.isEmpty else { return false }
        var didSync = false
        for pending in pendingTransactions {
            do {
                try await service.createTransaction(
                    groupId: pending.groupId,
                    description: pending.description,
                    amount: pending.amount,
                    paidBy: pending.paidBy,
                    type: pending.type,
                    date: pending.date,
                    splits: pending.splits.map {
                        (userId: $0.userId, percentage: $0.percentage, amount: $0.amount)
                    }
                )
                removePending(id: pending.id)
                didSync = true
            } catch {
                // Stop at first failure — network may have dropped again.
                break
            }
        }
        return didSync
    }

    // MARK: - Disk cache

    /// Snapshot of the data needed to render the dashboard offline.
    /// Balance is derived — not stored; it's recomputed from members + transactions.
    private struct CachedState: Codable {
        var ownerId: UUID?          // which user this cache belongs to
        var currentUser: Profile?
        var groups: [SplitGroup]
        var selectedGroupId: UUID?
        var members: [Profile]
        var transactions: [SplitTransaction]
    }

    private static let cacheEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private static let cacheDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    private func saveCachedState() {
        let state = CachedState(
            ownerId: currentUser?.id,
            currentUser: currentUser,
            groups: groups,
            selectedGroupId: selectedGroup?.id,
            members: members,
            transactions: transactions
        )
        guard let data = try? Self.cacheEncoder.encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }

    private func loadCachedState(for userId: UUID) {
        guard
            let data  = UserDefaults.standard.data(forKey: Self.cacheKey),
            let state = try? Self.cacheDecoder.decode(CachedState.self, from: data),
            state.ownerId == userId   // never load another user's cache (or a pre-ownerId cache)
        else { return }

        currentUser   = state.currentUser
        groups        = state.groups
        members       = state.members
        transactions  = state.transactions
        selectedGroup = state.groups.first(where: { $0.id == state.selectedGroupId })
                        ?? state.groups.first
        balances      = computeBalances()
    }

    // MARK: - Balance computation (only one direction stored per pair)

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
                let current = net[split.userId]?[paidBy] ?? 0
                net[split.userId]?[paidBy] = current + split.amount
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
                let toId   = netAmt > 0 ? b.id : a.id
                guard let from = profileMap[fromId], let to = profileMap[toId] else { continue }
                result.append(Balance(
                    fromUserId: fromId, toUserId: toId,
                    fromProfile: from, toProfile: to,
                    amount: abs(netAmt)
                ))
            }
        }
        return result
    }
}
