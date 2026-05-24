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

        case .signedIn:
            MainTabView()
                .task { await appVM.load() }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}
