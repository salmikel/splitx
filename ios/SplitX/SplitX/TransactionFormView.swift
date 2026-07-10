import SwiftUI

struct TransactionFormView: View {
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.dismiss) var dismiss

    var initialType: TransactionType = .expense
    var existing: SplitTransaction?

    @State private var type: TransactionType = .expense
    @State private var description = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var paidBy: UUID?
    @State private var splits: [UUID: Int] = [:]
    @State private var saving = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?
    /// Which member's percentage wheel is currently expanded (one at a time)
    @State private var expandedMemberId: UUID?

    private var isEditing: Bool { existing != nil }
    private var members: [Profile] { appVM.members }
    private var amount: Double { Double(amountText) ?? 0 }
    private var totalSplitPct: Int { splits.values.reduce(0, +) }
    private var isOfflineNew: Bool { !networkMonitor.isOnline && !isEditing }

    init(type: TransactionType = .expense) { self.initialType = type }
    init(existing: SplitTransaction) { self.existing = existing; self.initialType = existing.type }

    var body: some View {
        NavigationStack {
            // Form is a direct child of NavigationStack — no VStack wrapper —
            // so the first tap goes straight to the field without a "focus the
            // parent container" intermediate step.
            Form {
                // ── Type picker ───────────────────────────────────────
                Section {
                    Picker("Type", selection: $type) {
                        Label("Expense", systemImage: "creditcard.fill").tag(TransactionType.expense)
                        Label("Payment", systemImage: "arrow.up.circle.fill").tag(TransactionType.payment)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                // ── Details ───────────────────────────────────────────
                Section("Details") {
                    TextField(
                        type == .expense ? "Description (Dinner, groceries…)" : "Description (Payment to…)",
                        text: $description
                    )
                    .autocorrectionDisabled()

                    HStack {
                        Text(AppCurrency.symbol(for: appVM.currencyCode)).foregroundColor(.secondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    if !members.isEmpty {
                        Picker("Paid by", selection: Binding(
                            get: { paidBy ?? members.first?.id },
                            set: { paidBy = $0 }
                        )) {
                            ForEach(members) { m in
                                Text(m.id == appVM.currentUser?.id ? "\(m.name) (you)" : m.name)
                                    .tag(Optional(m.id))
                            }
                        }
                    }
                }

                // ── Split (expenses only) ─────────────────────────────
                if type == .expense {
                    Section {
                        ForEach(members) { member in
                            splitRow(for: member)
                        }
                    } header: {
                        HStack {
                            Text("Split")
                            Spacer()
                            Text("\(totalSplitPct)% of 100%")
                                .foregroundColor(totalSplitPct == 100 ? .green : .orange)
                        }
                    }

                    // Amount per person
                    if amount > 0 {
                        Section("Amount per Person") {
                            ForEach(members) { member in
                                let pct = Double(splits[member.id] ?? 0)
                                HStack {
                                    Text(member.id == appVM.currentUser?.id
                                         ? "\(member.name) (you)" : member.name)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text((pct / 100.0) * amount, format: .currency(code: appVM.currencyCode))
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                }

                // ── Error ─────────────────────────────────────────────
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundColor(.red).font(.footnote)
                    }
                }

                // ── Delete (edit mode only) ───────────────────────────
                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Transaction")
                                Spacer()
                            }
                        }
                    }
                }
            }
            // Offline banner sits just below the nav bar without wrapping the Form
            .safeAreaInset(edge: .top, spacing: 0) {
                if !networkMonitor.isOnline {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.footnote.weight(.semibold))
                        Text(isEditing
                             ? "Editing requires an internet connection."
                             : "You're offline. This transaction will be saved locally and synced when you reconnect.")
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.12))
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : isOfflineNew ? "Save Offline" : "Save") {
                        save()
                    }
                    .disabled(saving || description.isEmpty || amount <= 0
                              || (isEditing && !networkMonitor.isOnline))
                }
            }
            .navigationTitle(isEditing ? "Edit Transaction" : (type == .expense ? "New Expense" : "New Payment"))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if existing != nil {
                    setupInitialState(groupDefaults: nil)
                } else if let group = appVM.selectedGroup {
                    let fresh = (try? await SupabaseService.shared.fetchGroup(id: group.id)) ?? group
                    setupInitialState(groupDefaults: fresh)
                } else {
                    setupInitialState(groupDefaults: nil)
                }
            }
            .confirmationDialog(
                "Delete this transaction?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    // MARK: - Split row (tap-to-expand wheel)

    @ViewBuilder
    private func splitRow(for member: Profile) -> some View {
        let isExpanded = expandedMemberId == member.id
        let current = splits[member.id] ?? 0
        let label = member.id == appVM.currentUser?.id ? "\(member.name) (you)" : member.name

        VStack(spacing: 0) {
            // Tappable summary row
            HStack {
                Text(label)
                    .foregroundColor(.primary)
                Spacer()
                Text("\(current)%")
                    .foregroundColor(isExpanded ? .accentColor : .secondary)
                    .monospacedDigit()
                    .fontWeight(isExpanded ? .semibold : .regular)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedMemberId = isExpanded ? nil : member.id
                }
            }

            // Inline wheel — shown when this row is expanded
            if isExpanded {
                Picker("", selection: Binding(
                    get: { splits[member.id] ?? 0 },
                    set: { splits[member.id] = $0 }
                )) {
                    ForEach(0...100, id: \.self) { n in
                        Text("\(n)%").tag(n)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)
            }
        }
    }

    // MARK: - Setup

    private func setupInitialState(groupDefaults freshGroup: SplitGroup?) {
        type = initialType
        if let tx = existing {
            description = tx.description
            amountText = tx.amount.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(tx.amount)) : String(tx.amount)
            if let d = DateFormatter.isoDate.date(from: tx.date) { date = d }
            paidBy = tx.paidBy
            if let txSplits = tx.splits {
                for s in txSplits { splits[s.userId] = Int(s.percentage.rounded()) }
            }
        } else {
            let source = freshGroup ?? appVM.selectedGroup
            paidBy = source?.defaultPaidBy ?? appVM.currentUser?.id
            let defaults = source?.defaultSplits ?? [:]
            if defaults.isEmpty {
                splits = evenSplit(among: members)
            } else {
                for m in members {
                    splits[m.id] = defaults[m.id.uuidString.lowercased()]
                        .map { Int($0.rounded()) } ?? 0
                }
            }
        }
    }

    private func evenSplit(among members: [Profile]) -> [UUID: Int] {
        guard !members.isEmpty else { return [:] }
        let base = 100 / members.count
        let remainder = 100 % members.count
        return Dictionary(uniqueKeysWithValues: members.enumerated().map { i, m in
            (m.id, base + (i < remainder ? 1 : 0))
        })
    }

    // MARK: - Save / Delete

    private func buildSplitEntries(paid: UUID) -> [(userId: UUID, percentage: Double, amount: Double)] {
        if type == .expense {
            return members.map { m in
                let pct = Double(splits[m.id] ?? 0)
                return (userId: m.id, percentage: pct, amount: (pct / 100.0) * amount)
            }
        } else {
            let others = members.filter { $0.id != paid }
            return [
                (userId: paid, percentage: 0, amount: 0),
                others.first.map { (userId: $0.id, percentage: 100, amount: amount) }
            ].compactMap { $0 }
        }
    }

    private func validate() -> Bool {
        errorMessage = nil
        guard !description.isEmpty else { errorMessage = "Description required"; return false }
        guard amount > 0 else { errorMessage = "Enter a valid amount"; return false }
        if type == .expense, totalSplitPct != 100 {
            errorMessage = "Splits must total 100% (currently \(totalSplitPct)%)"
            return false
        }
        return true
    }

    private func save() {
        guard validate() else { return }
        guard let groupId = appVM.selectedGroup?.id,
              let paid = paidBy ?? members.first?.id else { return }

        let dateStr = DateFormatter.isoDate.string(from: date)
        let splitEntries = buildSplitEntries(paid: paid)

        if !networkMonitor.isOnline && !isEditing {
            appVM.enqueuePending(PendingTransaction(
                id: UUID(), groupId: groupId, description: description,
                amount: amount, paidBy: paid, type: type, date: dateStr,
                splits: splitEntries.map {
                    PendingTransaction.SplitEntry(userId: $0.userId,
                                                  percentage: $0.percentage,
                                                  amount: $0.amount)
                },
                queuedAt: Date()
            ))
            dismiss(); return
        }

        saving = true
        Task {
            do {
                if let tx = existing {
                    try await SupabaseService.shared.updateTransaction(
                        id: tx.id, description: description, amount: amount,
                        paidBy: paid, type: type, date: dateStr, splits: splitEntries)
                } else {
                    try await SupabaseService.shared.createTransaction(
                        groupId: groupId, description: description, amount: amount,
                        paidBy: paid, type: type, date: dateStr, splits: splitEntries)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                saving = false
            }
        }
    }

    private func delete() {
        guard let tx = existing else { return }
        Task {
            try? await SupabaseService.shared.deleteTransaction(id: tx.id)
            dismiss()
        }
    }
}

extension DateFormatter {
    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
