import Foundation
import StoreKit

/// Manages the "SplitX Premium" auto-renewing subscription (removes ads).
///
/// Uses StoreKit 2. Entitlement is derived from `Transaction.currentEntitlements`
/// (the source of truth Apple recommends), and a background task listens for
/// `Transaction.updates` so renewals, refunds, and purchases made on other
/// devices are reflected without a restart.
@MainActor
final class SubscriptionManager: ObservableObject {
    /// Must match the product ID created in App Store Connect and in the
    /// local `.storekit` configuration used for testing.
    static let yearlyProductID = "com.splitx.app.premium.yearly"

    /// Free tier: at most this many transactions total. Premium: this many
    /// transactions per calendar year. Sharing groups (inviting members and
    /// bulk CSV import) is Premium-only.
    static let freeTransactionLimit = 20
    static let premiumYearlyTransactionLimit = 1000
    /// Free tier is limited to a single group.
    static let freeGroupLimit = 1

    @Published private(set) var product: Product?
    @Published private(set) var isPremium = false
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = listenForTransactionUpdates()
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit { updatesTask?.cancel() }

    /// Localized price string for the paywall, e.g. "$4.99".
    var displayPrice: String { product?.displayPrice ?? "" }

    // MARK: - Entitlement gating

    /// Whether the user may create another transaction given current counts.
    /// Free is capped at a total; Premium is capped per year.
    func canCreateTransaction(totalCount: Int, thisYearCount: Int) -> Bool {
        isPremium
            ? thisYearCount < Self.premiumYearlyTransactionLimit
            : totalCount < Self.freeTransactionLimit
    }

    /// The active transaction cap, for display in the UI.
    var transactionLimit: Int {
        isPremium ? Self.premiumYearlyTransactionLimit : Self.freeTransactionLimit
    }

    /// Sharing a group (inviting members, bulk import) requires Premium.
    var canShareGroups: Bool { isPremium }

    /// Whether the user may create another group. Free is capped at one.
    func canCreateGroup(currentCount: Int) -> Bool {
        isPremium || currentCount < Self.freeGroupLimit
    }

    // MARK: - Loading

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.yearlyProductID])
            product = products.first
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Recomputes `isPremium` from the current entitlements.
    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.yearlyProductID,
               transaction.revocationDate == nil {
                active = true
            }
        }
        isPremium = active
    }

    // MARK: - Purchase / restore

    @discardableResult
    func purchase() async -> Bool {
        guard let product else {
            errorMessage = "Subscription is not available right now."
            return false
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = "Could not verify the purchase."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                return isPremium
            case .userCancelled:
                return false
            case .pending:
                errorMessage = "Purchase is pending approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Restores purchases (required by App Store Guideline 3.1.1 for the paywall).
    func restore() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPremium {
                errorMessage = "No active subscription found to restore."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Updates listener

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self.refreshEntitlements()
            }
        }
    }
}
