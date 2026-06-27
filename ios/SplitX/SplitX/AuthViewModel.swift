import Foundation
import AuthenticationServices
import CryptoKit
import Supabase

// MARK: - Auth State

enum AuthState {
    case loading
    case signedOut
    case awaitingMagicLink(email: String)
    case signedIn
    /// Apple sign-in found an existing profile with the same email.
    /// Carries the Apple credential so the user can either link or continue separately.
    case promptLinkAccount(email: String, idToken: String, nonce: String)
}

// MARK: - AuthViewModel

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var state: AuthState = .loading
    @Published var errorMessage: String?
    @Published var hasAppleLinked = false

    /// Stored when user chooses to link Apple to an existing email account.
    /// After the magic-link completes we use this to call linkIdentityWithIdToken.
    private var pendingAppleCredential: (idToken: String, nonce: String)?

    init() {
        Task { await checkSession() }
    }

    // MARK: - Session check

    func checkSession() async {
        // authStateChanges fires .initialSession synchronously from the local
        // keychain — no network call required, so this works offline too.
        for await (event, session) in supabase.auth.authStateChanges {
            guard case .initialSession = event else { continue }
            if session != nil {
                hasAppleLinked = await appleIsLinked()
                state = .signedIn
            } else {
                state = .signedOut
            }
            return
        }
    }

    // MARK: - Email / magic link

    func signIn(email: String) async {
        errorMessage = nil
        do {
            try await supabase.auth.signInWithOTP(
                email: email,
                redirectTo: URL(string: "splitx://auth/callback")
            )
            state = .awaitingMagicLink(email: email)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleDeepLink(_ url: URL) async {
        guard url.scheme == "splitx" else { return }
        do {
            try await supabase.auth.session(from: url)

            // If we have a pending Apple credential (user chose to link),
            // complete the identity link now that they're authenticated via email.
            if let pending = pendingAppleCredential {
                pendingAppleCredential = nil
                do {
                    try await supabase.auth.linkIdentityWithIdToken(
                        credentials: OpenIDConnectCredentials(
                            provider: .apple,
                            idToken: pending.idToken,
                            nonce: pending.nonce
                        )
                    )
                    hasAppleLinked = true
                } catch {
                    // Link failed — not fatal, user is still signed in via email.
                    errorMessage = "Accounts signed in, but Apple link failed: \(error.localizedDescription)"
                }
            } else {
                hasAppleLinked = await appleIsLinked()
            }
            state = .signedIn
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Apple sign-in

    func handleAppleResult(_ result: Result<ASAuthorization, Error>, nonce: String) async {
        errorMessage = nil
        do {
            let authorization = try result.get()
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData   = credential.identityToken,
                let idToken     = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Failed to read Apple credentials."
                return
            }

            let session = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
            let userId = session.user.id
            let email  = session.user.email ?? ""

            // Returning Apple user — profile already exists.
            if (try? await SupabaseService.shared.fetchProfile(id: userId)) != nil {
                hasAppleLinked = await appleIsLinked()
                state = .signedIn
                return
            }

            // New Apple user — check whether a profile with this email already exists
            // (i.e. the user previously signed in via magic link).
            if !email.isEmpty,
               (try? await SupabaseService.shared.fetchProfileByEmail(email: email)) != nil {
                // Prompt: link or keep separate?
                state = .promptLinkAccount(email: email, idToken: idToken, nonce: nonce)
            } else {
                // Genuinely new user — seed the profile with their Apple name.
                let firstName = credential.fullName?.givenName ?? ""
                let lastName  = credential.fullName?.familyName ?? ""
                let fullName  = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
                if !fullName.isEmpty {
                    try? await SupabaseService.shared.updateProfile(id: userId, displayName: fullName)
                }
                hasAppleLinked = await appleIsLinked()
                state = .signedIn
            }
        } catch {
            // Ignore user-cancelled Apple sheet.
            let ns = error as NSError
            if ns.domain == ASAuthorizationError.errorDomain,
               ns.code   == ASAuthorizationError.canceled.rawValue { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Link-account prompt actions

    /// User chose to link Apple with their existing email account.
    /// Sign out the new Apple session, send a magic link to the existing email,
    /// and store the Apple credential so we can link after the OTP completes.
    func confirmLinkAccount(email: String, idToken: String, nonce: String) async {
        try? await supabase.auth.signOut()
        pendingAppleCredential = (idToken: idToken, nonce: nonce)
        do {
            try await supabase.auth.signInWithOTP(
                email: email,
                redirectTo: URL(string: "splitx://auth/callback")
            )
            state = .awaitingMagicLink(email: email)
        } catch {
            pendingAppleCredential = nil
            errorMessage = error.localizedDescription
            state = .signedOut
        }
    }

    /// User chose NOT to link — continue with a brand-new Apple-only account.
    func skipLinkAccount(idToken: String, nonce: String) async {
        // Current session is already the new Apple user; just seed their profile.
        if let user = try? await supabase.auth.user() {
            try? await SupabaseService.shared.updateProfile(id: user.id, displayName: nil)
        }
        hasAppleLinked = await appleIsLinked()
        state = .signedIn
    }

    // MARK: - Link Apple from Settings

    func linkAppleIdentity(idToken: String, nonce: String) async {
        do {
            try await supabase.auth.linkIdentityWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
            hasAppleLinked = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sign out

    func signOut() async {
        try? await supabase.auth.signOut()
        hasAppleLinked = false
        state = .signedOut
    }

    // MARK: - Helpers

    private func appleIsLinked() async -> Bool {
        let identities = (try? await supabase.auth.userIdentities()) ?? []
        return identities.contains { $0.provider == "apple" }
    }
}

// MARK: - Nonce helpers (Sign in with Apple)

func randomNonceString(length: Int = 32) -> String {
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remaining = length
    while remaining > 0 {
        (0..<16).forEach { _ in
            guard remaining > 0 else { return }
            var byte: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
            if byte < charset.count {
                result.append(charset[Int(byte)])
                remaining -= 1
            }
        }
    }
    return result
}

func sha256Hex(_ input: String) -> String {
    let data   = Data(input.utf8)
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}
