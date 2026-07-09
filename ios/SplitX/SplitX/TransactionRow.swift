import SwiftUI

struct TransactionRow: View {
    let transaction: SplitTransaction
    let members: [Profile]
    let currentUserId: UUID?
    var currencyCode: String = "USD"

    private var paidByProfile: Profile? {
        members.first { $0.id == transaction.paidBy }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: transaction.date) else { return transaction.date }
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private var myShare: Double? {
        guard let uid = currentUserId,
              let splits = transaction.splits else { return nil }
        return splits.first { $0.userId == uid }?.amount
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(transaction.type == .payment
                          ? Color.green.opacity(0.15)
                          : Color.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: transaction.type == .payment ? "arrow.up.circle.fill" : "creditcard.fill")
                    .font(.system(size: 20))
                    .foregroundColor(transaction.type == .payment ? .green : .accentColor)
            }

            // Description + meta
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(formattedDate)
                    Text("·")
                    Text("\(paidByProfile?.name ?? "Unknown") paid")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            // Amount — green for payments, primary for expenses
            VStack(alignment: .trailing, spacing: 2) {
                Text(transaction.amount, format: .currency(code: currencyCode))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(transaction.type == .payment ? .green : .primary)
                if let share = myShare, let uid = currentUserId, transaction.paidBy != uid, transaction.type == .expense {
                    Text("you owe \(share, format: .currency(code: currencyCode))")
                        .font(.caption2)
                        .foregroundColor(.red)
                } else if let share = myShare, transaction.paidBy == currentUserId, share > 0, transaction.type == .expense {
                    Text("others owe you")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
