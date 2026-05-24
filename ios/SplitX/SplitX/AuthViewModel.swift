import Foundation
import Supabase

enum AuthState {
    case loading
    case signedOut
    case awaitingMagicLink(email: String)
    case signedIn
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var state: AuthState = .loading
    @Published var errorMessage: String?

    init() {
        Task { await checkSession() }
    }

    func checkSession() async {
        do {
            _ = try await supabase.auth.user()
            state = .signedIn
        } catch {
            state = .signedOut
        }
    }

    func signIn(email: String) async {
        errorMessage = nil
        do {
            // splitx://auth/callback must be added to Supabase allowed redirect URLs
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
            state = .signedIn
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        try? await supabase.auth.signOut()
        state = .signedOut
    }
}
