import SwiftUI
import WatchKit

/// Confirmation after saving: shows the iPhone's answer when it arrives, then
/// returns to the + screen on its own (tap to return sooner).
struct WatchConfirmationView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager

    let expense: WatchExpense
    let currencyCode: String

    @Environment(\.dismiss) private var dismiss

    private var reply: WatchSaveReply? { connectivity.replies[expense.id] }
    private var isRejected: Bool { reply?.status == .rejected }

    private var status: String {
        switch reply?.status {
        case .saved:    return "Saved to \(connectivity.config.groupName)"
        case .queued:   return "On your iPhone. Uploads when it's back online."
        case .rejected: return reply?.message ?? "Not saved."
        case nil:
            return connectivity.isPhoneReachable
                ? "Sending to iPhone…"
                : "Syncs when your iPhone is nearby"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: isRejected ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(isRejected ? .red : .green)
            Text(expense.amount, format: .currency(code: currencyCode))
                .font(.headline)
            Text(expense.description)
                .font(.footnote)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(status)
                .font(.caption2)
                .foregroundStyle(isRejected ? .red : .secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .onChange(of: isRejected) { _, rejected in
            if rejected { WKInterfaceDevice.current().play(.failure) }
        }
        .task {
            // Give the iPhone a few seconds to answer, then leave the result
            // up long enough to read (longer for an error).
            var waited = 0
            while reply == nil, connectivity.isPhoneReachable, waited < 40, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                waited += 1
            }
            try? await Task.sleep(for: .seconds(isRejected ? 4 : 1.5))
            if !Task.isCancelled { dismiss() }
        }
    }
}
