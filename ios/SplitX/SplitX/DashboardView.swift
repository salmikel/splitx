import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var showNewExpense = false
    @State private var showNewPayment = false
    @State private var selectedTransaction: SplitTransaction?

    var body: some View {
        NavigationStack {
            Group {
                if appVM.isLoading && appVM.transactions.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if appVM.selectedGroup == nil {
                    EmptyGroupView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20, pinnedViews: []) {
                            BalanceSummarySection()
                            ActionButtonsRow(
                                onExpense: { showNewExpense = true },
                                onPayment: { showNewPayment = true }
                            )
                            TransactionListSection(selectedTransaction: $selectedTransaction)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                    .refreshable { await appVM.refresh() }
                }
            }
            .navigationTitle(appVM.selectedGroup?.name ?? "SplitX")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showNewExpense, onDismiss: { Task { await appVM.refresh() } }) {
                TransactionFormView(type: .expense)
            }
            .sheet(isPresented: $showNewPayment, onDismiss: { Task { await appVM.refresh() } }) {
                TransactionFormView(type: .payment)
            }
            .sheet(item: $selectedTransaction, onDismiss: { Task { await appVM.refresh() } }) { tx in
                TransactionFormView(existing: tx)
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

            Text(balance.amount, format: .currency(code: "USD"))
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

// MARK: - Transaction List

struct TransactionListSection: View {
    @EnvironmentObject var appVM: AppViewModel
    @Binding var selectedTransaction: SplitTransaction?

    var body: some View {
        if !appVM.transactions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Transactions")
                VStack(spacing: 0) {
                    ForEach(appVM.transactions) { tx in
                        TransactionRow(
                            transaction: tx,
                            members: appVM.members,
                            currentUserId: appVM.currentUser?.id
                        )
                        .onTapGesture { selectedTransaction = tx }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("No transactions yet")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(40)
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
