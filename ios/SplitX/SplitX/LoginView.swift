import SwiftUI
import AuthenticationServices

// MARK: - Login View

struct LoginView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var email = ""
    @State private var isLoading = false
    @State private var currentNonce = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            VStack(spacing: 12) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 90, height: 90)
                    .cornerRadius(20)
                Text("SplitX")
                    .font(.system(size: 30, weight: .bold))
                Text("Split expenses effortlessly")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 48)

            // Sign in with Apple
            SignInWithAppleButton(.signIn) { request in
                let nonce = randomNonceString()
                currentNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = sha256Hex(nonce)
            } onCompletion: { result in
                Task { await auth.handleAppleResult(result, nonce: currentNonce) }
            }
            .frame(maxWidth: .infinity, maxHeight: 50)
            .cornerRadius(12)
            .padding(.horizontal, 20)

            // Divider
            HStack {
                Rectangle().fill(Color(.separator)).frame(height: 1)
                Text("or").font(.caption).foregroundColor(.secondary).padding(.horizontal, 8)
                Rectangle().fill(Color(.separator)).frame(height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            // Email field
            VStack(spacing: 0) {
                HStack {
                    Text("Email")
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .leading)
                    TextField("you@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { signIn() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            if let error = auth.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            // Continue with Email
            Button(action: signIn) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Continue with Email")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(email.contains("@") ? Color.accentColor : Color.accentColor.opacity(0.4))
            .cornerRadius(12)
            .padding(.horizontal, 20)
            .disabled(!email.contains("@") || isLoading)

            Text("We'll send a magic link — no password needed.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .padding(.horizontal, 40)

            Spacer()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private func signIn() {
        guard email.contains("@") else { return }
        isLoading = true
        Task {
            await auth.signIn(email: email.trimmingCharacters(in: .whitespaces).lowercased())
            isLoading = false
        }
    }
}

// MARK: - Magic Link Sent

struct MagicLinkSentView: View {
    @EnvironmentObject var auth: AuthViewModel
    let email: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("✉️").font(.system(size: 60))
            Text("Check your email")
                .font(.title2.bold())
            Text("We sent a magic link to **\(email)**.\nTap the link to sign in.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("Use a different email") {
                auth.state = .signedOut
            }
            .font(.subheadline)
            Spacer()
        }
        .padding(32)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

// MARK: - Link Account Prompt

struct LinkAccountPromptView: View {
    @EnvironmentObject var auth: AuthViewModel
    let email: String
    let idToken: String
    let nonce: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.accentColor)

                Text("Existing Account Found")
                    .font(.title2.bold())

                Text("A SplitX account already exists for **\(email)**. Would you like to link your Apple ID with that account so you can sign in with either?")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 32)
            }
            .padding(.bottom, 48)

            VStack(spacing: 12) {
                Button {
                    Task { await auth.confirmLinkAccount(email: email, idToken: idToken, nonce: nonce) }
                } label: {
                    Text("Yes, Link My Accounts")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }

                Button {
                    Task { await auth.skipLinkAccount(idToken: idToken, nonce: nonce) }
                } label: {
                    Text("No, Continue as New Account")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 20)

            if let error = auth.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            Spacer()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}
