import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var email = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.accentColor)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Text("S")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(.white)
                    )
                Text("SplitX")
                    .font(.system(size: 30, weight: .bold))
                Text("Split expenses effortlessly")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 48)

            // Form card
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
                .padding(.top, 12)
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
