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
        // Re-check the StoreKit entitlement whenever a user signs in (e.g. an
        // Apple Family member on a new device), keeping isPremium current.
        Task { [weak self] in
            for await (event, session) in supabase.auth.authStateChanges {
                if session != nil, event == .signedIn || event == .initialSession {
                    await self?.refreshEntitlements()
                }
            }
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
        errorMessage = nil
        do {
            let products = try await Product.products(for: [Self.yearlyProductID])
            product = products.first
            if product == nil {
                errorMessage = "Couldn't find \u{201C}\(Self.yearlyProductID)\u{201D} in the store. Check that the subscription exists in App Store Connect with that exact ID and is \u{201C}Ready to Submit,\u{201D} and that the Paid Apps agreement is active. New products can take a few hours to appear."
            }
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
        // Note: profiles.premium_until (which the web reads) is written server
        // side by the verified App Store Server Notification, not the client.
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
            // Tag the purchase with the user's Supabase UUID so App Store Server
            // Notifications can map the entitlement back to this account.
            var options: Set<Product.PurchaseOption> = []
            if let userId = supabase.auth.currentUser?.id {
                options.insert(.appAccountToken(userId))
            }
            let result = try await product.purchase(options: options)
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
