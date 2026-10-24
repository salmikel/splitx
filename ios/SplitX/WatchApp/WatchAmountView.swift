import SwiftUI
import WatchKit

/// Digit-grid amount entry. Saving builds a `WatchExpense` for the configured
/// group and hands it back to the root view to send to the iPhone.
struct WatchAmountView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager

    @State var description: String
    let onSave: (WatchExpense) -> Void

    @State private var amountText = ""

    init(description: String, onSave: @escaping (WatchExpense) -> Void) {
        _description = State(initialValue: description)
        self.onSave = onSave
    }

    private var config: WatchConfig { connectivity.config }
    private var amount: Double { Double(amountText) ?? 0 }

    /// Currencies like JPY have no minor unit, so the decimal key is disabled.
    private var fractionDigits: Int {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = config.currencyCode
        return f.maximumFractionDigits
    }

    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "⌫"]]
    private let keySpacing: CGFloat = 3

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                // Tap the description to rewrite it.
                TextFieldLink(prompt: Text("Description")) {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } onSubmit: { text in
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { description = trimmed }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Text("\(config.currencySymbol)\(amountText.isEmpty ? "0" : amountText)")
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
            }

            // Size the keys from the space left, so all four rows fit on every
            // Watch size (system button styles have too large a minimum height).
            GeometryReader { geo in
                let keyHeight = (geo.size.height - keySpacing * CGFloat(rows.count - 1)) / CGFloat(rows.count)
                Grid(horizontalSpacing: keySpacing, verticalSpacing: keySpacing) {
                    ForEach(rows, id: \.self) { row in
                        GridRow {
                            ForEach(row, id: \.self) { key in
                                Button { tap(key) } label: {
                                    Group {
                                        if key == "⌫" {
                                            Image(systemName: "delete.left")
                                        } else {
                                            Text(key)
                                        }
                                    }
                                    .font(.title3.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: keyHeight)
                                }
                                .buttonStyle(KeypadButtonStyle())
                                .disabled(key == "." && fractionDigits == 0)
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { save() } label: { Image(systemName: "checkmark") }
                    .disabled(amount <= 0)
                    .accessibilityLabel("Save expense")
            }
        }
    }

    private func tap(_ key: String) {
        WKInterfaceDevice.current().play(.click)
        switch key {
        case "⌫":
            if !amountText.isEmpty { amountText.removeLast() }
        case ".":
            guard fractionDigits > 0, !amountText.contains(".") else { return }
            amountText = amountText.isEmpty ? "0." : amountText + "."
        default:
            if let dot = amountText.firstIndex(of: ".") {
                // Cap the minor units at the currency's precision.
                guard amountText.distance(from: dot, to: amountText.endIndex) <= fractionDigits else { return }
            } else if amountText.count >= 7 {
                return
            }
            amountText = amountText == "0" ? key : amountText + key
        }
    }

    private func save() {
        guard amount > 0, let groupId = config.groupId else { return }
        WKInterfaceDevice.current().play(.success)
        onSave(WatchExpense(
            id: UUID(),
            groupId: groupId,
            description: description,
            amount: amount,
            createdAt: Date()
        ))
    }
}

/// Compact rounded key that fills whatever frame the grid gives it.
private struct KeypadButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.4))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(configuration.isPressed ? 0.55 : 0.28))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
