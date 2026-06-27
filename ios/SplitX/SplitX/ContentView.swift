import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var appVM: AppViewModel

    var body: some View {
        switch auth.state {
        case .loading:
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ProgressView()
            }

        case .signedOut:
            LoginView()

        case .awaitingMagicLink(let email):
            MagicLinkSentView(email: email)

        case .promptLinkAccount(let email, let idToken, let nonce):
            LinkAccountPromptView(email: email, idToken: idToken, nonce: nonce)

        case .signedIn:
            MainTabView()
                .task { await appVM.load() }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        DashboardView()
    }
}
