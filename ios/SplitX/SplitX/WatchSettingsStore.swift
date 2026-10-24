import Foundation
import Supabase

/// Apple Watch preferences chosen in iPhone Settings: which group the Watch
/// logs expenses into, who pays, and the default split among members.
/// Persisted in UserDefaults and wiped on sign-out.
@MainActor
final class WatchSettingsStore: ObservableObject {
    @Published private(set) var groupId: UUID?
    @Published private(set) var paidBy: UUID?
    /// Member UUID (lowercased string) → percentage, same convention as
    /// `SplitGroup.defaultSplits`.
    @Published private(set) var splits: [String: Double] = [:]

    private static let storageKey = "splitx.watchSettings.v1"

    private struct Stored: Codable {
        var groupId: UUID?
        var paidBy: UUID?
        var splits: [String: Double]
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            groupId = stored.groupId
            paidBy = stored.paidBy
            splits = stored.splits
        }
        observeAuthSignOut()
    }

    func save(groupId: UUID?, paidBy: UUID?, splits: [String: Double]) {
        self.groupId = groupId
        self.paidBy = paidBy
        self.splits = splits
        let data = try? JSONEncoder().encode(Stored(groupId: groupId, paidBy: paidBy, splits: splits))
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    /// Never let the next account on this device inherit the previous user's
    /// Watch group (mirrors AppViewModel.purgeLocalData).
    private func observeAuthSignOut() {
        Task { [weak self] in
            for await (event, _) in supabase.auth.authStateChanges {
                guard let self else { return }
                if event == .signedOut {
                    self.groupId = nil
                    self.paidBy = nil
                    self.splits = [:]
                    UserDefaults.standard.removeObject(forKey: Self.storageKey)
                }
            }
        }
    }
}
