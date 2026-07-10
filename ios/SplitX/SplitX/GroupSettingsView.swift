import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Group Settings View

struct GroupSettingsView: View {
    let initialGroup: SplitGroup

    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var subscriptions: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var showPaywall = false

    @State private var group: SplitGroup
    @State private var members: [Profile] = []
    @State private var allGroups: [SplitGroup] = []
    @State private var invitations: [Invitation] = []
    @State private var loading = true

    // Defaults
    @State private var defaultPaidById: UUID?
    @State private var defaultSplitPcts: [UUID: String] = [:]
    @State private var savingDefaults = false
    @State private var defaultsMessage: String?

    // Currency
    @State private var currencyMessage: String?

    // Delete group
    @State private var showDeleteGroupConfirm = false
    @State private var deletingGroup = false
    @State private var deleteGroupError: String?

    // Invite
    @State private var inviteEmail = ""
    @State private var inviting = false
    @State private var inviteMessage: String?

    // Remove member
    @State private var memberToRemove: Profile?
    @State private var replacementId: UUID?
    @State private var removingMember = false
    @State private var removeError: String?

    // CSV Import
    @State private var csvTargetGroupId: UUID
    @State private var showFilePicker = false
    @State private var csvMessage: String?
    @State private var csvLoading = false

    // Export / Template
    @State private var exportLoading = false
    @State private var exportShareURL: URL?
    @State private var showShareSheet = false

    init(group: SplitGroup) {
        self.initialGroup = group
        _group = State(initialValue: group)
        _csvTargetGroupId = State(initialValue: group.id)
    }

    private var isCreator: Bool { group.createdBy == appVM.currentUser?.id }
    /// At least 3 members required so removal always leaves ≥ 2.
    private var canRemoveMembers: Bool { isCreator && members.count >= 3 }

    var body: some View {
        Group {
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    membersSection
                    currencySection
                    defaultSettingsSection
                    inviteSection
                    if !invitations.isEmpty { pendingInvitesSection }
                    exportSection
                    importSection
                    if isCreator { deleteGroupSection }
                }
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.commaSeparatedText, .text],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleCSVImport(result: result) }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportShareURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(item: $memberToRemove) { toRemove in
            removeMemberSheet(for: toRemove)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subscriptions)
        }
        .alert("Delete Group?", isPresented: $showDeleteGroupConfirm) {
            Button("Delete", role: .destructive) { Task { await doDeleteGroup() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \"\(group.name)\" and all of its expenses, payments, and balances for every member. This can't be undone.")
        }
    }

    // MARK: - Sections

    private var membersSection: some View {
        Section {
            ForEach(members) { member in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text(member.initial)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name).fontWeight(.medium)
                        Text(member.email).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    if member.id == appVM.currentUser?.id {
                        Text("You")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(10)
                    } else if canRemoveMembers {
                        Button {
                            removeError = nil
                            replacementId = members.first { $0.id != member.id }?.id
                            memberToRemove = member
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            HStack {
                Text("Members")
                if isCreator && members.count < 3 {
                    Spacer()
                    Text("Need 3+ members to remove")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .textCase(nil)
                }
            }
        }
    }

    // MARK: - Remove Member Sheet

    @ViewBuilder
    private func removeMemberSheet(for member: Profile) -> some View {
        let others = members.filter { $0.id != member.id }
        NavigationStack {
            Form {
                Section {
                    Text("Removing \(member.name) will reassign all of their paid transactions and split shares to the selected member.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("Transfer to") {
                    Picker("Replacement member", selection: Binding(
                        get: { replacementId ?? others.first?.id },
                        set: { replacementId = $0 }
                    )) {
                        ForEach(others) { m in
                            Text(m.id == appVM.currentUser?.id ? "\(m.name) (you)" : m.name)
                                .tag(Optional(m.id))
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                if let err = removeError {
                    Section {
                        Text(err).foregroundColor(.red).font(.footnote)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task { await doRemoveMember(member) }
                    } label: {
                        HStack {
                            Spacer()
                            Text(removingMember ? "Removing…" : "Remove \(member.name)")
                            Spacer()
                        }
                    }
                    .disabled(removingMember)
                }
            }
            .navigationTitle("Remove Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        memberToRemove = nil
                        removeError = nil
                    }
                    .disabled(removingMember)
                }
            }
        }
    }

    private func doRemoveMember(_ member: Profile) async {
        guard let repId = replacementId ?? members.first(where: { $0.id != member.id })?.id else { return }
        removingMember = true
        removeError = nil
        do {
            try await SupabaseService.shared.removeMember(
                groupId: group.id,
                removedUserId: member.id,
                replacementUserId: repId,
                currentDefaultPaidBy: group.defaultPaidBy,
                currentDefaultSplits: group.defaultSplits
            )
            memberToRemove = nil
            await load()
            if group.id == appVM.selectedGroup?.id { await appVM.refresh() }
        } catch {
            removeError = error.localizedDescription
        }
        removingMember = false
    }

    private var currencySection: some View {
        Section {
            if isCreator {
                Picker("Currency", selection: Binding(
                    get: { group.currency },
                    set: { saveCurrency($0) }
                )) {
                    ForEach(AppCurrency.all, id: \.code) { c in
                        Text("\(c.name) (\(c.symbol))").tag(c.code)
                    }
                }
                if let msg = currencyMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(msg.starts(with: "Error") ? .red : .green)
                }
            } else {
                HStack {
                    Text("Currency")
                    Spacer()
                    Text("\(AppCurrency.name(for: group.currency)) (\(AppCurrency.symbol(for: group.currency)))")
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Currency")
        } footer: {
            Text(isCreator
                 ? "Applies to all amounts shown in this group."
                 : "Only the group creator can change the currency.")
        }
    }

    private var defaultSettingsSection: some View {
        Section {
            if !members.isEmpty {
                Picker("Default Paid by", selection: Binding(
                    get: { defaultPaidById ?? members.first?.id },
                    set: { defaultPaidById = $0 }
                )) {
                    ForEach(members) { m in
                        Text(m.id == appVM.currentUser?.id ? "\(m.name) (you)" : m.name)
                            .tag(Optional(m.id))
                    }
                }

                ForEach(members) { member in
                    HStack {
                        Text(member.id == appVM.currentUser?.id ? "\(member.name) (you)" : member.name)
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 2) {
                            TextField("0", text: Binding(
                                get: { defaultSplitPcts[member.id] ?? "0" },
                                set: { defaultSplitPcts[member.id] = $0 }
                            ))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            Text("%").foregroundColor(.secondary)
                        }
                    }
                }

                Button(savingDefaults ? "Saving…" : "Save Defaults") { saveDefaults() }
                    .disabled(savingDefaults)

                if let msg = defaultsMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(msg.starts(with: "Error") ? .red : .green)
                }
            }
        } header: {
            Text("Default Settings")
        }
    }

    private var inviteSection: some View {
        Section {
            if subscriptions.canShareGroups {
                HStack {
                    TextField("friend@example.com", text: $inviteEmail)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    Button(inviting ? "Sending…" : "Invite") { sendInvite() }
                        .disabled(inviting || !inviteEmail.contains("@"))
                        .foregroundColor(.accentColor)
                }
                if let msg = inviteMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(msg.starts(with: "Error") ? .red : .green)
                }
            } else {
                PremiumLockedRow(
                    title: "Invite members",
                    subtitle: "Group sharing is a Premium feature.",
                    onUpgrade: { showPaywall = true }
                )
            }
        } header: {
            Text("Invite Members")
        }
    }

    private var pendingInvitesSection: some View {
        Section("Pending Invites") {
            ForEach(invitations) { inv in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(inv.email)
                        Text("Expires \(inv.expiresAt, style: .date)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Revoke") {
                        Task {
                            try? await SupabaseService.shared.deleteInvitation(id: inv.id)
                            await loadInvitations()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
        }
    }

    private var exportSection: some View {
        Section("Export") {
            Button {
                Task { await prepareExport(template: false) }
            } label: {
                Label(exportLoading ? "Preparing…" : "Export Expenses", systemImage: "square.and.arrow.up")
            }
            .disabled(exportLoading)

            Button {
                Task { await prepareExport(template: true) }
            } label: {
                Label("Download Template", systemImage: "doc.badge.plus")
            }
        }
    }

    @ViewBuilder
    private var importSection: some View {
        Section {
            if !subscriptions.canShareGroups {
                PremiumLockedRow(
                    title: "Import from CSV",
                    subtitle: "Bulk import is a Premium feature.",
                    onUpgrade: { showPaywall = true }
                )
            } else {
            // Group selector — only when user belongs to multiple groups
            if allGroups.count > 1 {
                Picker("Import into", selection: $csvTargetGroupId) {
                    ForEach(allGroups) { g in
                        Text(g.name).tag(g.id)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Columns: **Date**, **Description**, **Amount**, **Paid By**, then **Percentage Owed by [Name]** for each member.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(csvLoading ? "Importing…" : "Choose CSV File") {
                    showFilePicker = true
                }
                .disabled(csvLoading)

                if let msg = csvMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(msg.starts(with: "Error") || msg.contains("Missing") ? .red : .green)
                }
            }
            .padding(.vertical, 4)
            }
        } header: {
            Text("Import CSV")
        }
    }

    private var deleteGroupSection: some View {
        Section {
            Button(role: .destructive) {
                deleteGroupError = nil
                showDeleteGroupConfirm = true
            } label: {
                HStack {
                    Spacer()
                    if deletingGroup {
                        ProgressView()
                    } else {
                        Text("Delete Group")
                    }
                    Spacer()
                }
            }
            .disabled(deletingGroup)

            if let err = deleteGroupError {
                Text(err).font(.caption).foregroundColor(.red)
            }
        } footer: {
            Text("Only the group creator can delete the group. This removes it for all members.")
        }
    }

    // MARK: - Delete group

    private func doDeleteGroup() async {
        deletingGroup = true
        deleteGroupError = nil
        do {
            try await SupabaseService.shared.deleteGroup(id: group.id)
            await appVM.load()          // refresh groups; selects another or shows empty state
            dismiss()                   // pop back to Settings
        } catch {
            deleteGroupError = "Error: \(error.localizedDescription)"
            deletingGroup = false
        }
    }

    // MARK: - Load

    private func load() async {
        if let g = try? await SupabaseService.shared.fetchGroup(id: initialGroup.id) { group = g }
        let loadedMembers = (try? await SupabaseService.shared.fetchMembers(groupId: initialGroup.id)) ?? []
        members = loadedMembers
        invitations = (try? await SupabaseService.shared.fetchPendingInvitations(groupId: initialGroup.id)) ?? []
        if let user = appVM.currentUser {
            allGroups = (try? await SupabaseService.shared.fetchGroups(userId: user.id)) ?? [group]
        } else {
            allGroups = [group]
        }

        // Set up defaults from the freshly loaded group.
        // If defaultSplits already has entries for some members, any member
        // not yet listed gets 0% rather than an even-share fallback —
        // that way adding a new member never pushes the total above 100%.
        defaultPaidById = group.defaultPaidBy
        let hasExistingDefaults = !group.defaultSplits.isEmpty
        let even = loadedMembers.isEmpty ? "0" : String(format: "%.2f", 100.0 / Double(loadedMembers.count))
        defaultSplitPcts = [:]
        for m in loadedMembers {
            defaultSplitPcts[m.id] = group.defaultSplits[m.id.uuidString.lowercased()].map { String($0) }
                ?? (hasExistingDefaults ? "0" : even)
        }

        loading = false
    }

    private func loadInvitations() async {
        invitations = (try? await SupabaseService.shared.fetchPendingInvitations(groupId: group.id)) ?? []
    }

    // MARK: - Defaults

    private func saveDefaults() {
        savingDefaults = true
        defaultsMessage = nil
        let splitsObj: [String: Double] = Dictionary(uniqueKeysWithValues:
            members.map { m in (m.id.uuidString.lowercased(), Double(defaultSplitPcts[m.id] ?? "0") ?? 0) }
        )
        Task {
            do {
                try await SupabaseService.shared.updateGroupDefaults(
                    id: group.id,
                    defaultPaidBy: defaultPaidById,
                    defaultSplits: splitsObj
                )
                defaultsMessage = "Defaults saved."
                // Refresh appVM if this is the active group
                if group.id == appVM.selectedGroup?.id { await appVM.load() }
            } catch {
                defaultsMessage = "Error: \(error.localizedDescription)"
            }
            savingDefaults = false
        }
    }

    // MARK: - Currency

    private func saveCurrency(_ code: String) {
        guard code != group.currency else { return }
        group.currency = code               // optimistic local update
        currencyMessage = nil
        Task {
            do {
                try await SupabaseService.shared.updateGroupCurrency(id: group.id, currency: code)
                currencyMessage = "Currency updated."
                if group.id == appVM.selectedGroup?.id { await appVM.load() }
            } catch {
                currencyMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Invite

    private func sendInvite() {
        guard let user = appVM.currentUser else { return }
        inviting = true
        inviteMessage = nil
        let email = inviteEmail.trimmingCharacters(in: .whitespaces).lowercased()
        let inviterName = user.displayName ?? user.email
        Task {
            do {
                try await SupabaseService.shared.sendInvitation(
                    groupId: group.id,
                    groupName: group.name,
                    inviterName: inviterName,
                    email: email
                )
                inviteMessage = "Invitation sent to \(email)"
                inviteEmail = ""
                await loadInvitations()
            } catch {
                inviteMessage = "Error: \(error.localizedDescription)"
            }
            inviting = false
        }
    }

    // MARK: - Export

    private func prepareExport(template: Bool) async {
        exportLoading = true
        defer { exportLoading = false }

        do {
            let txs: [SplitTransaction] = template ? [] : (try await SupabaseService.shared.fetchTransactions(groupId: group.id))
            let headers = ["Date", "Description", "Amount", "Paid By"]
                + members.map { "Percentage Owed by \($0.name)" }

            var rows: [[String]] = [headers]

            if template {
                let even = members.isEmpty ? "0" : String(format: "%.2f", 100.0 / Double(members.count))
                rows.append(["2025-01-15", "Sample expense", "100.00",
                             members.first?.name ?? "Name"]
                             + members.map { _ in even })
            } else {
                for tx in txs {
                    let paidName = members.first { $0.id == tx.paidBy }?.name ?? ""
                    let pcts = members.map { m -> String in
                        guard let split = tx.splits?.first(where: { $0.userId == m.id }) else { return "0" }
                        return String(split.percentage)
                    }
                    rows.append([tx.date, tx.description, String(tx.amount), paidName] + pcts)
                }
            }

            let csv = rows.map { row in
                row.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",")
            }.joined(separator: "\n")

            let filename = template ? "\(group.name)-template.csv" : "\(group.name)-export.csv"
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try csv.write(to: tmpURL, atomically: true, encoding: .utf8)
            exportShareURL = tmpURL
            showShareSheet = true
        } catch {
            csvMessage = "Export error: \(error.localizedDescription)"
        }
    }

    // MARK: - CSV Import

    private func handleCSVImport(result: Result<[URL], Error>) async {
        csvMessage = nil
        csvLoading = true
        defer { csvLoading = false }

        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            // Load members for the target group (may differ from current group)
            let targetMembers: [Profile]
            if csvTargetGroupId == group.id {
                targetMembers = members
            } else {
                targetMembers = (try? await SupabaseService.shared.fetchMembers(groupId: csvTargetGroupId)) ?? members
            }

            let text = try String(contentsOf: url, encoding: .utf8)

            // Normalise line endings (Windows \r\n → \n, old Mac \r → \n)
            let normalised = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r",   with: "\n")
            let lines = normalised.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard lines.count > 1 else { csvMessage = "CSV is empty"; return }

            // Use a proper quoted-CSV parser so commas inside values and
            // quote-wrapped fields (as produced by the exporter) are handled correctly.
            let headers = Self.parseCSVRow(lines[0])
            let dateIdx = headers.firstIndex { $0.range(of: "date",    options: .caseInsensitive) != nil }
            let descIdx = headers.firstIndex { $0.range(of: "desc",    options: .caseInsensitive) != nil }
            let amtIdx  = headers.firstIndex { $0.range(of: "amount",  options: .caseInsensitive) != nil }
            let paidIdx = headers.firstIndex { $0.range(of: "paid.*by", options: [.caseInsensitive, .regularExpression]) != nil }

            guard let di = dateIdx, let de = descIdx, let ai = amtIdx, let pi = paidIdx else {
                csvMessage = "Missing columns: Date, Description, Amount, Paid By"
                return
            }

            // Map "Percentage Owed by <Name>" columns → member profiles
            let pctCols: [(idx: Int, profile: Profile)] = headers.enumerated().compactMap { idx, h in
                guard h.range(of: "(?i)percentage owed by ", options: .regularExpression) != nil else { return nil }
                let name = h
                    .replacingOccurrences(of: "(?i)percentage owed by ", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                guard let profile = targetMembers.first(where: {
                    $0.name.lowercased()  == name.lowercased() ||
                    $0.email.lowercased() == name.lowercased()
                }) else { return nil }
                return (idx: idx, profile: profile)
            }

            var imported = 0, skipped = 0
            let fmt = DateFormatter.isoDate

            for i in 1..<lines.count {
                let cols = Self.parseCSVRow(lines[i])
                guard cols.count > max(di, de, ai, pi),
                      let amount = Double(cols[ai].replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")),
                      amount > 0,
                      !cols[de].isEmpty else { skipped += 1; continue }

                let parsedDate = fmt.date(from: cols[di]).map { fmt.string(from: $0) } ?? cols[di]
                let paidBy = targetMembers.first {
                    $0.name.lowercased()  == cols[pi].lowercased() ||
                    $0.email.lowercased() == cols[pi].lowercased()
                }

                let splitEntries: [(userId: UUID, percentage: Double, amount: Double)] = pctCols.compactMap { col in
                    guard col.idx < cols.count,
                          let pct = Double(cols[col.idx]) else { return nil }
                    return (userId: col.profile.id, percentage: pct, amount: (pct / 100.0) * amount)
                }

                do {
                    try await SupabaseService.shared.createTransaction(
                        groupId: csvTargetGroupId,
                        description: cols[de],
                        amount: amount,
                        paidBy: paidBy?.id ?? (appVM.currentUser?.id ?? targetMembers[0].id),
                        type: .expense,
                        date: parsedDate,
                        splits: splitEntries
                    )
                    imported += 1
                } catch { skipped += 1 }
            }

            csvMessage = "Imported \(imported) transaction\(imported == 1 ? "" : "s")" +
                         (skipped > 0 ? ", skipped \(skipped)." : ".")
            if csvTargetGroupId == appVM.selectedGroup?.id { await appVM.refresh() }
        } catch {
            csvMessage = "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Quoted CSV row parser
    //
    // Handles RFC-4180 CSV: fields may be wrapped in double-quotes, commas
    // inside quoted fields are treated as data, and "" inside a quoted field
    // represents a literal quote character.

    private static func parseCSVRow(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var idx = line.startIndex

        while idx < line.endIndex {
            let ch = line[idx]
            if inQuotes {
                if ch == "\"" {
                    let next = line.index(after: idx)
                    if next < line.endIndex && line[next] == "\"" {
                        // Escaped quote inside a quoted field: "" → "
                        field.append("\"")
                        idx = line.index(after: next)
                    } else {
                        // Closing quote
                        inQuotes = false
                        idx = next
                    }
                } else {
                    field.append(ch)
                    idx = line.index(after: idx)
                }
            } else {
                if ch == "\"" {
                    inQuotes = true
                    idx = line.index(after: idx)
                } else if ch == "," {
                    fields.append(field.trimmingCharacters(in: .whitespaces))
                    field = ""
                    idx = line.index(after: idx)
                } else {
                    field.append(ch)
                    idx = line.index(after: idx)
                }
            }
        }
        fields.append(field.trimmingCharacters(in: .whitespaces))
        return fields
    }
}

// MARK: - Premium Locked Row

/// Grayed-out placeholder shown in place of a Premium-only feature for free
/// users, with an upgrade call to action.
struct PremiumLockedRow: View {
    let title: String
    let subtitle: String
    let onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundColor(.secondary)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            Button(action: onUpgrade) {
                Label("Upgrade to Premium", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}
