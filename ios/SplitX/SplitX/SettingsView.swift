import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var auth: AuthViewModel

    @State private var inviteEmail = ""
    @State private var inviting = false
    @State private var inviteMessage: String?
    @State private var pendingInvitations: [Invitation] = []

    @State private var newGroupName = ""
    @State private var showCreateGroup = false
    @State private var creatingGroup = false

    @State private var displayName = ""
    @State private var savingProfile = false

    @State private var showFilePicker = false
    @State private var csvMessage: String?
    @State private var csvLoading = false

    var body: some View {
        NavigationStack {
            Form {
                // Profile section
                Section("Profile") {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Your name", text: $displayName)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                    }
                    LabeledContent("Email", value: appVM.currentUser?.email ?? "")
                    Button(savingProfile ? "Saving…" : "Save Profile") { saveProfile() }
                        .disabled(savingProfile)
                }

                // Group section
                if let group = appVM.selectedGroup {
                    Section("Group · \(group.name)") {
                        ForEach(appVM.members) { member in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 36, height: 36)
                                    .overlay(Text(member.initial).font(.system(size: 15, weight: .semibold)).foregroundColor(.white))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name).fontWeight(.medium)
                                    Text(member.email).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if member.id == appVM.currentUser?.id {
                                    Text("You")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.accentColor.opacity(0.1))
                                        .cornerRadius(10)
                                }
                            }
                        }
                    }

                    // Invite section
                    Section {
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
                    } header: {
                        Text("Invite Members")
                    }

                    if !pendingInvitations.isEmpty {
                        Section("Pending Invites") {
                            ForEach(pendingInvitations) { inv in
                                HStack {
                                    Text(inv.email)
                                    Spacer()
                                    Text("Pending")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.1))
                                        .cornerRadius(10)
                                }
                            }
                        }
                    }

                    // CSV Import
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
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
                    } header: {
                        Text("Import CSV")
                    }

                } else {
                    Section {
                        if showCreateGroup {
                            TextField("Group name", text: $newGroupName)
                            Button(creatingGroup ? "Creating…" : "Create Group") { createGroup() }
                                .disabled(creatingGroup || newGroupName.isEmpty)
                        } else {
                            Button("Create a Group") { showCreateGroup = true }
                        }
                    } header: {
                        Text("Group")
                    }
                }

                // Sign out
                Section {
                    Button(role: .destructive) {
                        Task { await auth.signOut() }
                    } label: {
                        Text("Sign Out").frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { displayName = appVM.currentUser?.displayName ?? "" }
            .task { await loadInvitations() }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.commaSeparatedText, .text],
                allowsMultipleSelection: false
            ) { result in
                Task { await handleCSVImport(result: result) }
            }
        }
    }

    private func saveProfile() {
        guard let user = appVM.currentUser else { return }
        savingProfile = true
        Task {
            try? await SupabaseService.shared.updateProfile(id: user.id, displayName: displayName.isEmpty ? nil : displayName)
            await appVM.load()
            savingProfile = false
        }
    }

    private func sendInvite() {
        guard let group = appVM.selectedGroup, let user = appVM.currentUser else { return }
        inviting = true
        inviteMessage = nil
        Task {
            do {
                try await SupabaseService.shared.sendInvitation(groupId: group.id, invitedBy: user.id, email: inviteEmail.trimmingCharacters(in: .whitespaces).lowercased())
                inviteMessage = "Invitation sent to \(inviteEmail)"
                inviteEmail = ""
                await loadInvitations()
            } catch {
                inviteMessage = "Error: \(error.localizedDescription)"
            }
            inviting = false
        }
    }

    private func createGroup() {
        guard let user = appVM.currentUser else { return }
        creatingGroup = true
        Task {
            do {
                _ = try await SupabaseService.shared.createGroup(name: newGroupName.trimmingCharacters(in: .whitespaces), userId: user.id)
                await appVM.load()
                showCreateGroup = false
                newGroupName = ""
            } catch {}
            creatingGroup = false
        }
    }

    private func loadInvitations() async {
        guard let group = appVM.selectedGroup else { return }
        pendingInvitations = (try? await SupabaseService.shared.fetchPendingInvitations(groupId: group.id)) ?? []
    }

    private func handleCSVImport(result: Result<[URL], Error>) async {
        guard let group = appVM.selectedGroup else { return }
        csvMessage = nil
        csvLoading = true
        defer { csvLoading = false }

        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let text = try String(contentsOf: url, encoding: .utf8)
            let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard lines.count > 1 else { csvMessage = "CSV is empty"; return }

            let headers = lines[0].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let dateIdx = headers.firstIndex { $0.range(of: "date", options: .caseInsensitive) != nil }
            let descIdx = headers.firstIndex { $0.range(of: "desc", options: .caseInsensitive) != nil }
            let amtIdx = headers.firstIndex { $0.range(of: "amount", options: .caseInsensitive) != nil }
            let paidIdx = headers.firstIndex { $0.range(of: "paid.*by", options: [.caseInsensitive, .regularExpression]) != nil }

            guard let di = dateIdx, let de = descIdx, let ai = amtIdx, let pi = paidIdx else {
                csvMessage = "Missing columns: Date, Description, Amount, Paid By"
                return
            }

            // Find percentage columns
            let pctCols: [(idx: Int, name: String)] = headers.enumerated().compactMap { idx, h in
                guard let m = h.range(of: "percentage owed by (.+)", options: [.caseInsensitive, .regularExpression]) else { return nil }
                let name = String(h[m].dropFirst("Percentage Owed by ".count))
                return (idx: idx, name: name)
            }

            var imported = 0, skipped = 0
            let isoFmt = DateFormatter.isoDate

            for i in 1..<lines.count {
                let cols = lines[i].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard cols.count > max(di, de, ai, pi),
                      let amount = Double(cols[ai]), amount > 0,
                      !cols[de].isEmpty else { skipped += 1; continue }

                let rawDate = cols[di]
                let parsedDate = isoFmt.date(from: rawDate).map { isoFmt.string(from: $0) } ?? rawDate

                let paidByProfile = appVM.members.first {
                    $0.name.lowercased() == cols[pi].lowercased() || $0.email.lowercased() == cols[pi].lowercased()
                }

                var splitEntries: [(userId: UUID, percentage: Double, amount: Double)] = []
                for col in pctCols {
                    guard col.idx < cols.count, let pct = Double(cols[col.idx]) else { continue }
                    let profile = appVM.members.first {
                        $0.name.lowercased() == col.name.lowercased() || $0.email.lowercased() == col.name.lowercased()
                    }
                    guard let p = profile else { continue }
                    splitEntries.append((userId: p.id, percentage: pct, amount: (pct / 100) * amount))
                }

                do {
                    try await SupabaseService.shared.createTransaction(
                        groupId: group.id,
                        description: cols[de],
                        amount: amount,
                        paidBy: paidByProfile?.id ?? appVM.currentUser!.id,
                        type: .expense,
                        date: parsedDate,
                        splits: splitEntries
                    )
                    imported += 1
                } catch { skipped += 1 }
            }

            csvMessage = "Imported \(imported) transaction\(imported == 1 ? "" : "s")\(skipped > 0 ? ", skipped \(skipped)" : "")."
            await appVM.refresh()
        } catch {
            csvMessage = "Error: \(error.localizedDescription)"
        }
    }
}
