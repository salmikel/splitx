import SwiftUI

/// Opens to a large + button. Tapping it goes straight to the system text
/// input (Scribble finger-drawing / dictation) for the description, then to the
/// digit grid for the amount.
struct WatchRootView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager

    @State private var path: [String] = []        // pushed descriptions
    @State private var saved: WatchExpense?

    private var config: WatchConfig { connectivity.config }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !connectivity.hasReceivedConfig {
                    WatchNoticeView(
                        icon: "iphone",
                        title: "Open SplitX",
                        message: "Open SplitX on your iPhone to connect your Watch."
                    )
                } else if !config.isPremium {
                    WatchNoticeView(
                        icon: "lock.fill",
                        title: "SplitX Premium",
                        message: "Upgrade in SplitX on your iPhone to add expenses from your Watch."
                    )
                } else if !config.isConfigured {
                    WatchNoticeView(
                        icon: "person.3.fill",
                        title: "Choose a Group",
                        message: "On your iPhone, go to SplitX Settings → Apple Watch and pick a group."
                    )
                } else {
                    addButton
                }
            }
            .navigationTitle("SplitX")
            .navigationDestination(for: String.self) { description in
                WatchAmountView(description: description) { expense in
                    connectivity.send(expense)
                    saved = expense
                    path = []
                }
            }
        }
        .fullScreenCover(item: $saved) { expense in
            WatchConfirmationView(expense: expense, currencyCode: config.currencyCode)
                .environmentObject(connectivity)
        }
    }

    private var addButton: some View {
        VStack(spacing: 8) {
            TextFieldLink(prompt: Text("Description")) {
                Image(systemName: "plus")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(Circle().fill(Color.accentColor))
            } onSubmit: { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                path.append(trimmed)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add expense")

            Text(config.groupName)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Explains why the + button isn't available yet.
struct WatchNoticeView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text(title).font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
