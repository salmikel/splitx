import SwiftUI

struct TransactionFormView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss

    // Set for new transaction
    var initialType: TransactionType = .expense
    // Set for editing existing
    var existing: SplitTransaction?

    @State private var type: TransactionType = .expense
    @State private var description = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var paidBy: UUID?
    @State private var splits: [UUID: String] = [:]
    @State private var saving = false
    @State private var deleting = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    private var isEditing: Bool { existing != nil }
    private var members: [Profile] { appVM.members }
    private var amount: Double { Double(amountText) ?? 0 }

    private var totalSplitPct: Double {
        splits.values.compactMap { Double($0) }.reduce(0, +)
    }

    init(type: TransactionType = .expense) {
        self.initialType = type
    }

    init(existing: SplitTransaction) {
        self.existing = existing
        self.initialType = existing.type
    }

    var body: some View {
        NavigationStack {
            Form {
                // Type picker
                Section {
                    Picker("Type", selection: $type) {
                        Label("Expense", systemImage: "creditcard.fill").tag(TransactionType.expense)
                        Label("Payment", systemImage: "arrow.up.circle.fill").tag(TransactionType.payment)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                // Details
                Section("Details") {
                    TextField(type == .expense ? "Description (Dinner, groceries…)" : "Description (Payment to…)", text: $description)

                    HStack {
                        Text("$")
                            .foregroundColor(.secondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    if !members.isEmpty {
                        Picker("Paid by", selection: Binding(
                            get: { paidBy ?? members.first?.id },
                            set: { paidBy = $0 }
                        )) {
                            ForEach(members) { member in
                                Text(member.id == appVM.currentUser?.id ? "\(member.name) (you)" : member.name)
                                    .tag(Optional(member.id))
                            }
                        }
                    }
                }

                // Splits (only for expenses)
                if type == .expense {
                    Section {
                        ForEach(members) { member in
                            HStack {
                                Text(member.id == appVM.currentUser?.id ? "\(member.name) (you)" : member.name)
                                Spacer()
                                HStack(spacing: 2) {
                                    TextField("0", text: Binding(
                                        get: { splits[member.id] ?? "0" },
                                        set: { splits[member.id] = $0 }
                                    ))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)
                                    Text("%")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Split")
                            Spacer()
                            Text("\(totalSplitPct, specifier: "%.1f")% of 100%")
                                .foregroundColor(abs(totalSplitPct - 100) < 0.1 ? .green : .orange)
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }

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
            .navigationTitle(isEditing ? "Edit Transaction" : (type == .expense ? "New Expense" : "New Payment"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { save() }
                        .disabled(saving || description.isEmpty || amount <= 0)
                }
            }
            .onAppear { setupInitialState() }
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

    private func setupInitialState() {
        type = initialType
        if let tx = existing {
            description = tx.description
            amountText = String(tx.amount)
            if let d = DateFormatter.isoDate.date(from: tx.date) { date = d }
            paidBy = tx.paidBy
            if let txSplits = tx.splits {
                for s in txSplits { splits[s.userId] = String(s.percentage) }
            }
        } else {
            paidBy = appVM.currentUser?.id
            let even = members.isEmpty ? "0" : String(format: "%.2f", 100.0 / Double(members.count))
            for m in members { splits[m.id] = even }
        }
    }

    private func save() {
        errorMessage = nil
        guard !description.isEmpty else { errorMessage = "Description required"; return }
        guard amount > 0 else { errorMessage = "Enter a valid amount"; return }
        if type == .expense, abs(totalSplitPct - 100) > 0.1 {
            errorMessage = "Splits must total 100% (currently \(String(format: "%.1f", totalSplitPct))%)"
            return
        }

        guard let groupId = appVM.selectedGroup?.id,
              let paid = paidBy ?? members.first?.id else { return }

        let dateStr = DateFormatter.isoDate.string(from: date)
        let splitEntries: [(userId: UUID, percentage: Double, amount: Double)]

        if type == .expense {
            splitEntries = members.compactMap { m in
                let pct = Double(splits[m.id] ?? "0") ?? 0
                return (userId: m.id, percentage: pct, amount: (pct / 100) * amount)
            }
        } else {
            let others = members.filter { $0.id != paid }
            let payee = others.first
            splitEntries = [
                (userId: paid, percentage: 0, amount: 0),
                payee.map { (userId: $0.id, percentage: 100, amount: amount) }
            ].compactMap { $0 }
        }

        saving = true
        Task {
            do {
                if let tx = existing {
                    try await SupabaseService.shared.updateTransaction(
                        id: tx.id, description: description, amount: amount,
                        paidBy: paid, type: type, date: dateStr, splits: splitEntries
                    )
                } else {
                    try await SupabaseService.shared.createTransaction(
                        groupId: groupId, description: description, amount: amount,
                        paidBy: paid, type: type, date: dateStr, splits: splitEntries
                    )
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
        deleting = true
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
