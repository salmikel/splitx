import SwiftUI
import AuthenticationServices

struct SettingsView: View {
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var displayNameText = ""
    @State private var savingProfile = false

    @State private var newGroupName = ""
    @State private var showCreateGroup = false
    @State private var creatingGroup = false

    // Apple linking from Settings
    @State private var linkNonce = ""
    @State private var linkError: String?

    // Account deletion
    @State private var showDeleteConfirm = false
    @State private var deletingAccount = false

    // Hosted legal documents (also linked from the subscription paywall).
    private let privacyPolicyURL = URL(string: "https://splitx.salvador-mikel.workers.dev/privacy")!
    private let termsURL = URL(string: "https://splitx.salvador-mikel.workers.dev/terms")!

    var body: some View {
        NavigationStack {
            Form {
                // ── Profile ──
                Section("Profile") {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Your name", text: $displayNameText)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                    }
                    LabeledContent("Email", value: appVM.currentUser?.email ?? "")
                    Button(savingProfile ? "Saving…" : "Save Profile") { saveProfile() }
                        .disabled(savingProfile)
                }

                // ── Connected Accounts ──
                Section {
                    // Email / magic link (always present)
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.accentColor)
                            .frame(width: 28)
                        Text("Email magic link")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    // Apple
                    if auth.hasAppleLinked {
                        HStack {
                            Image(systemName: "apple.logo")
                                .foregroundColor(.primary)
                                .frame(width: 28)
                            Text("Apple ID")
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    } else {
                        // Show Apple sign-in button to link
                        SignInWithAppleButton(.continue) { request in
                            let nonce = randomNonceString()
                            linkNonce = nonce
                            request.requestedScopes = []  // email already known
                            request.nonce = sha256Hex(nonce)
                        } onCompletion: { result in
                            Task { await handleAppleLink(result: result) }
                        }
                        .frame(height: 44)
                        .cornerRadius(8)

                        if let err = linkError {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                } header: {
                    Text("Connected Accounts")
                } footer: {
                    if !auth.hasAppleLinked {
                        Text("Link your Apple ID to sign in faster without a magic link email.")
                    }
                }

                // ── Groups ──
                Section {
                    ForEach(appVM.groups) { group in
                        NavigationLink(destination: GroupSettingsView(group: group)) {
                            Text(group.name).font(.body)
                        }
                    }

                    if showCreateGroup {
                        TextField("Group name", text: $newGroupName)
                            .autocorrectionDisabled()
                        Button(creatingGroup ? "Creating…" : "Create Group") { createGroup() }
                            .disabled(creatingGroup || newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Cancel") { showCreateGroup = false; newGroupName = "" }
                            .foregroundColor(.secondary)
                    } else {
                        Button("+ New Group") { showCreateGroup = true }
                            .foregroundColor(.accentColor)
                    }
                } header: {
                    Text("Groups")
                }

                // ── About / Legal ──
                Section("About") {
                    Link(destination: privacyPolicyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: termsURL) {
                        Label("Terms of Use", systemImage: "doc.text")
                    }
                    LabeledContent("Version", value: appVersion)
                }

                // ── Sign Out ──
                Section {
                    Button(role: .destructive) {
                        Task { await auth.signOut() }
                    } label: {
                        Text("Sign Out").frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                // ── Delete Account ──
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            if deletingAccount {
                                ProgressView()
                            } else {
                                Text("Delete Account")
                            }
                            Spacer()
                        }
                    }
                    .disabled(deletingAccount)
                } footer: {
                    Text("Permanently deletes your account and personal data. This can't be undone.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { displayNameText = appVM.currentUser?.displayName ?? "" }
            .alert("Delete Account?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteAccount() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account and personal data. Shared transactions in groups you belong to will remain for the other members. This can't be undone.")
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    // MARK: - Actions

    private func saveProfile() {
        guard let user = appVM.currentUser else { return }
        savingProfile = true
        Task {
            try? await SupabaseService.shared.updateProfile(
                id: user.id,
                displayName: displayNameText.isEmpty ? nil : displayNameText
            )
            await appVM.load()
            savingProfile = false
        }
    }

    private func createGroup() {
        guard let user = appVM.currentUser else { return }
        creatingGroup = true
        Task {
            do {
                _ = try await SupabaseService.shared.createGroup(
                    name: newGroupName.trimmingCharacters(in: .whitespaces),
                    userId: user.id
                )
                await appVM.load()
                showCreateGroup = false
                newGroupName = ""
            } catch {}
            creatingGroup = false
        }
    }

    private func deleteAccount() {
        deletingAccount = true
        Task {
            await auth.deleteAccount()
            deletingAccount = false
            // On success the auth state flips to .signedOut and this view is
            // torn down automatically; on failure auth.errorMessage is set.
        }
    }

    private func handleAppleLink(result: Result<ASAuthorization, Error>) async {
        linkError = nil
        do {
            let authorization = try result.get()
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData  = credential.identityToken,
                let idToken    = String(data: tokenData, encoding: .utf8)
            else {
                linkError = "Could not read Apple credential."
                return
            }
            await auth.linkAppleIdentity(idToken: idToken, nonce: linkNonce)
            if let err = auth.errorMessage { linkError = err }
        } catch {
            let ns = error as NSError
            if ns.domain == ASAuthorizationError.errorDomain,
               ns.code   == ASAuthorizationError.canceled.rawValue { return }
            linkError = error.localizedDescription
        }
    }
}
