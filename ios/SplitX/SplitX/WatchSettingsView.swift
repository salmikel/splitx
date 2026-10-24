import SwiftUI

/// Apple Watch settings (Premium): which group the Watch logs expenses into,
/// who pays, and how those expenses are split among the group's members.
struct WatchSettingsView: View {
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var watchSettings: WatchSettingsStore

    @State private var groupId: UUID?
    @State private var paidBy: UUID?
    @State private var splitPcts: [UUID: String] = [:]
    @State private var members: [Profile] = []
    @State private var loadingMembers = false
    @State private var message: String?
    @State private var didSeed = false

    private var totalPct: Double {
        members.reduce(0) { $0 + (Double(splitPcts[$1.id] ?? "") ?? 0) }
    }
    private var totalIsValid: Bool { abs(totalPct - 100) < 0.01 }

    var body: some View {
        Form {
            Section {
                Picker("Group", selection: $groupId) {
                    Text("None").tag(UUID?.none)
                    ForEach(appVM.groups) { g in
                        Text(g.name).tag(Optional(g.id))
                    }
                }
            } header: {
                Text("Watch Group")
            } footer: {
                Text("Expenses you add on your Apple Watch are saved to this group.")
            }

            if groupId != nil {
                if loadingMembers {
                    Section { ProgressView().frame(maxWidth: .infinity) }
                } else if !members.isEmpty {
                    Section("Paid by") {
                        Picker("Paid by", selection: Binding(
                            get: { paidBy ?? members.first?.id },
                            set: { paidBy = $0 }
                        )) {
                            ForEach(members) { m in
                                Text(label(for: m)).tag(Optional(m.id))
                            }
                        }
                    }

                    Section {
                        ForEach(members) { member in
                            HStack {
                                Text(label(for: member))
                                    .foregroundColor(.secondary)
                                Spacer()
                                HStack(spacing: 2) {
                                    TextField("0", text: Binding(
                                        get: { splitPcts[member.id] ?? "0" },
                                        set: { splitPcts[member.id] = $0 }
                                    ))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)
                                    Text("%").foregroundColor(.secondary)
                                }
                            }
                        }
                        Button("Split Evenly") { splitPcts = evenSplit(members) }
                    } header: {
                        HStack {
                            Text("Default Allocation")
                            Spacer()
                            Text("\(totalPct, specifier: "%.0f")% of 100%")
                                .foregroundColor(totalIsValid ? .green : .orange)
                        }
                    }
                }
            }

            Section {
                Button("Save") { save() }
                    .disabled(groupId != nil && (members.isEmpty || !totalIsValid))
                if let message {
                    Text(message).font(.caption).foregroundColor(.green)
                }
            } footer: {
                Text("Open SplitX on your Apple Watch and tap + to add an expense. It's saved here when your iPhone receives it.")
            }
        }
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // onAppear re-fires when returning from the Group picker's push
            // screen; only seed once so an unsaved selection isn't reset.
            guard !didSeed else { return }
            didSeed = true
            groupId = watchSettings.groupId.flatMap { id in appVM.groups.first { $0.id == id }?.id }
                ?? appVM.selectedGroup?.id
        }
        .task(id: groupId) { await loadMembers() }
    }

    private func label(for member: Profile) -> String {
        member.id == appVM.currentUser?.id ? "\(member.name) (you)" : member.name
    }

    // MARK: - Load

    /// Loads the chosen group's members and seeds the form from the saved Watch
    /// settings, falling back to the group's own defaults, then an even split.
    private func loadMembers() async {
        message = nil
        guard let id = groupId, let group = appVM.groups.first(where: { $0.id == id }) else {
            members = []
            return
        }
        loadingMembers = true
        defer { loadingMembers = false }

        let loaded = id == appVM.selectedGroup?.id
            ? appVM.members
            : ((try? await SupabaseService.shared.fetchMembers(groupId: id)) ?? [])
        members = loaded

        let saved = watchSettings.groupId == id ? watchSettings.splits : [:]
        let source = !saved.isEmpty ? saved : group.defaultSplits
        if source.isEmpty {
            splitPcts = evenSplit(loaded)
        } else {
            splitPcts = Dictionary(uniqueKeysWithValues: loaded.map { m in
                (m.id, source[m.id.uuidString.lowercased()].map { format($0) } ?? "0")
            })
        }

        let savedPaidBy = watchSettings.groupId == id ? watchSettings.paidBy : nil
        let candidate = savedPaidBy ?? group.defaultPaidBy ?? appVM.currentUser?.id
        paidBy = loaded.contains { $0.id == candidate } ? candidate : loaded.first?.id
    }

    private func evenSplit(_ members: [Profile]) -> [UUID: String] {
        guard !members.isEmpty else { return [:] }
        let share = format(100.0 / Double(members.count))
        return Dictionary(uniqueKeysWithValues: members.map { ($0.id, share) })
    }

    private func format(_ pct: Double) -> String {
        pct.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(pct)) : String(format: "%.2f", pct)
    }

    // MARK: - Save

    private func save() {
        let splits: [String: Double] = groupId == nil ? [:] : Dictionary(uniqueKeysWithValues:
            members.map { ($0.id.uuidString.lowercased(), Double(splitPcts[$0.id] ?? "") ?? 0) }
        )
        watchSettings.save(groupId: groupId, paidBy: groupId == nil ? nil : paidBy, splits: splits)
        message = groupId == nil ? "Apple Watch logging turned off." : "Saved. Your Watch is up to date."
    }
}
