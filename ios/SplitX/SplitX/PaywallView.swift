import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var subscriptions: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    private let privacyPolicyURL = URL(string: "https://splitx.salvador-mikel.workers.dev/privacy")!
    private let termsURL = URL(string: "https://splitx.salvador-mikel.workers.dev/terms")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                        Text("SplitX Premium")
                            .font(.title.bold())
                        Text("Enjoy SplitX with no ads.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 24)

                    // Benefits
                    VStack(alignment: .leading, spacing: 14) {
                        benefit("rectangle.slash", "Remove all ads")
                        benefit("bolt.fill", "Support ongoing development")
                        benefit("checkmark.seal.fill", "Everything in the free version")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(16)

                    // Subscribe
                    VStack(spacing: 8) {
                        Button {
                            Task {
                                let ok = await subscriptions.purchase()
                                if ok { dismiss() }
                            }
                        } label: {
                            Group {
                                if subscriptions.isWorking {
                                    ProgressView().tint(.white)
                                } else if subscriptions.displayPrice.isEmpty {
                                    Text("Subscribe")
                                } else {
                                    Text("Subscribe — \(subscriptions.displayPrice)/year")
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accentColor)
                            .cornerRadius(14)
                        }
                        .disabled(subscriptions.isWorking || subscriptions.product == nil)

                        Button("Restore Purchases") {
                            Task { await subscriptions.restore() }
                        }
                        .font(.subheadline)
                        .disabled(subscriptions.isWorking)
                    }

                    if let error = subscriptions.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }

                    // Required subscription disclosure (Guideline 3.1.2)
                    Text("SplitX Premium is an auto-renewing annual subscription. Payment is charged to your Apple ID at confirmation of purchase. It renews automatically for the same price and duration unless canceled at least 24 hours before the end of the current period. Manage or cancel anytime in your device Settings.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)

                    HStack(spacing: 16) {
                        Link("Terms of Use", destination: termsURL)
                        Text("·").foregroundColor(.secondary)
                        Link("Privacy Policy", destination: privacyPolicyURL)
                    }
                    .font(.caption)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func benefit(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 26)
            Text(text)
            Spacer()
        }
    }
}
