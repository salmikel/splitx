import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showNewExpense = false
    @State private var showNewPayment = false
    @State private var selectedTransaction: SplitTransaction?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if appVM.isLoading && appVM.transactions.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if appVM.selectedGroup == nil {
                    EmptyGroupView()
                } else {
                    dashboardContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").fontWeight(.medium)
                    }
                }
                ToolbarItem(placement: .principal) {
                    if appVM.groups.count > 1 {
                        Menu {
                            ForEach(appVM.groups) { group in
                                Button {
                                    Task { await appVM.selectGroup(group) }
                                } label: {
                                    if group.id == appVM.selectedGroup?.id {
                                        Label(group.name, systemImage: "checkmark")
                                    } else {
                                        Text(group.name)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                VStack(spacing: 1) {
                                    Text(appVM.selectedGroup?.name ?? "SplitX")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text("\(appVM.members.count) members")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    } else {
                        VStack(spacing: 1) {
                            Text(appVM.selectedGroup?.name ?? "SplitX")
                                .font(.headline)
                            Text("\(appVM.members.count) members")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showNewExpense, onDismiss: { Task { await appVM.refresh() } }) {
                TransactionFormView(type: .expense)
            }
            .sheet(isPresented: $showNewPayment, onDismiss: { Task { await appVM.refresh() } }) {
                TransactionFormView(type: .payment)
            }
            .sheet(item: $selectedTransaction, onDismiss: { Task { await appVM.refresh() } }) { tx in
                TransactionFormView(existing: tx)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - Adaptive layout

    /// Chooses a layout based on device size class and orientation:
    /// • iPhone (compact): single stacked column — the original layout.
    /// • iPad portrait: a centered, width-constrained column so content
    ///   doesn't stretch across the full screen.
    /// • iPad landscape: a two-pane split with balances + actions in a
    ///   sidebar and the transaction list filling the remaining width.
    @ViewBuilder
    private var dashboardContent: some View {
        if horizontalSizeClass == .regular {
            GeometryReader { geo in
                if geo.size.width > geo.size.height {
                    // ── iPad landscape: two-pane split ───────────────────
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            statusBanner
                            ScrollView {
                                headerSection
                                    .padding(20)
                            }
                        }
                        .frame(width: 380)
                        .background(Color(.systemGroupedBackground))

                        Divider()

                        transactionList
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    // ── iPad portrait: centered, width-constrained ───────
                    VStack(spacing: 0) {
                        statusBanner
                        headerSection
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 12)
                        transactionList
                    }
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                }
            }
        } else {
            // ── iPhone: original single-column layout ────────────────────
            VStack(spacing: 0) {
                statusBanner
                headerSection
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                transactionList
            }
        }
    }

    /// Offline / syncing banner shown above the content.
    @ViewBuilder
    private var statusBanner: some View {
        if appVM.isSyncing {
            StatusBanner(
                icon: "arrow.triangle.2.circlepath",
                text: "Syncing saved transactions…",
                color: .blue,
                spinning: true
            )
        } else if !networkMonitor.isOnline {
            StatusBanner(
                icon: "wifi.slash",
                text: "You're offline. New transactions will be saved locally.",
                color: .orange
            )
        }
    }

    /// Balances summary + the expense/payment action buttons.
    private var headerSection: some View {
        VStack(spacing: 16) {
            BalanceSummarySection()
            ActionButtonsRow(
                onExpense: { showNewExpense = true },
                onPayment: { showNewPayment = true }
            )
        }
    }

    /// Scrollable transaction list (native List) — handles scroll,
    /// swipe-to-delete, separators, and pull-to-refresh.
    private var transactionList: some View {
        List {
            PendingTransactionsSection()
            TransactionListSection(selectedTransaction: $selectedTransaction)
        }
        .listStyle(.insetGrouped)
        .refreshable { await appVM.refresh() }
    }
}

// MARK: - Status Banner

struct StatusBanner: View {
    let icon: String
    let text: String
    let color: Color
    var spinning: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if spinning {
                ProgressView()
                    .tint(color)
                    .scaleEffect(0.8)
            } else {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
            }
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .foregroundColor(color)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(color.opacity(0.12))
    }
}

// MARK: - Pending Transactions (List section)

struct PendingTransactionsSection: View {
    @EnvironmentObject var appVM: AppViewModel

    var body: some View {
        let pending = appVM.pendingForCurrentGroup
        if !pending.isEmpty {
            Section {
                ForEach(pending) { tx in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tx.description)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(tx.date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(tx.amount, format: .currency(code: appVM.currencyCode))
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                            Label("Offline", systemImage: "clock")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .listRowBackground(Color.orange.opacity(0.05))
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Pending Sync")
                    Spacer()
                    Text("\(pending.count) queued")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .textCase(nil)
                }
            }
        }
    }
}

// MARK: - Balance Summary

struct BalanceSummarySection: View {
    @EnvironmentObject var appVM: AppViewModel

    var body: some View {
        if !appVM.balances.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Balances")
                VStack(spacing: 0) {
                    ForEach(appVM.balances) { balance in
                        BalanceRow(balance: balance)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
        } else if !appVM.transactions.isEmpty {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("All settled up!")
                    .fontWeight(.medium)
                    .foregroundColor(.green)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
}

struct BalanceRow: View {
    @EnvironmentObject var appVM: AppViewModel
    let balance: Balance

    var iOwe: Bool { balance.fromUserId == appVM.currentUser?.id }
    var theyOwe: Bool { balance.toUserId == appVM.currentUser?.id }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if iOwe {
                    (Text("You owe ") + Text(balance.toProfile.name).bold())
                } else if theyOwe {
                    (Text(balance.fromProfile.name).bold() + Text(" owes you"))
                } else {
                    (Text(balance.fromProfile.name).bold() + Text(" owes ") + Text(balance.toProfile.name).bold())
                }
            }
            .font(.subheadline)

            Spacer()

            Text(balance.amount, format: .currency(code: appVM.currencyCode))
                .fontWeight(.semibold)
                .foregroundColor(iOwe ? .red : theyOwe ? .green : .primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if balance.id != appVM.balances.last?.id {
                Divider().padding(.leading, 16)
            }
        }
    }
}

// MARK: - Action Buttons

struct ActionButtonsRow: View {
    let onExpense: () -> Void
    let onPayment: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onExpense) {
                Label("Expense", systemImage: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            Button(action: onPayment) {
                Label("Payment", systemImage: "arrow.up")
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
            }
        }
    }
}

// MARK: - Transaction List (List section)

struct TransactionListSection: View {
    @EnvironmentObject var appVM: AppViewModel
    @Binding var selectedTransaction: SplitTransaction?

    var body: some View {
        Section("Transactions") {
            if appVM.transactions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No transactions yet")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(appVM.transactions) { tx in
                    TransactionRow(
                        transaction: tx,
                        members: appVM.members,
                        currentUserId: appVM.currentUser?.id,
                        currencyCode: appVM.currencyCode
                    )
                    // Zero out List's default insets — TransactionRow owns its padding
                    .listRowInsets(EdgeInsets())
                    .onTapGesture { selectedTransaction = tx }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await appVM.deleteTransaction(tx) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Empty State

struct EmptyGroupView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Group Yet")
                .font(.title2.bold())
            Text("Create a group in Settings to start splitting expenses.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Shared Components

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.footnote)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .padding(.leading, 4)
    }
}
