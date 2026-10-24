import SwiftUI

/// Brief "saved" confirmation that returns to the + screen on its own.
struct WatchConfirmationView: View {
    let expense: WatchExpense
    let currencyCode: String
    /// Whether the iPhone was reachable when the expense was sent.
    let delivered: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text(expense.amount, format: .currency(code: currencyCode))
                .font(.headline)
            Text(expense.description)
                .font(.footnote)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(delivered ? "Sent to iPhone" : "Will sync when your iPhone is nearby")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .task {
            try? await Task.sleep(for: .seconds(2))
            dismiss()
        }
    }
}
