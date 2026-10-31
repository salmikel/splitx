import SwiftUI
import WidgetKit

// Watch face complication for SplitX. It carries no live data — its only job is
// to put SplitX on the watch face so a tap launches the Watch app (watchOS
// launches a complication's owning app automatically). That app opens straight
// to the big "+" add-expense button.
//
// This file belongs to the SplitXComplication widget-extension target only.
// WidgetKit accessory complications need watchOS 9+; our deployment target is
// watchOS 10.0.

/// A single, unchanging timeline entry. There's nothing to refresh, so the
/// timeline is one entry that never expires.
struct SplitXEntry: TimelineEntry {
    let date: Date
}

struct SplitXProvider: TimelineProvider {
    func placeholder(in context: Context) -> SplitXEntry {
        SplitXEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SplitXEntry) -> Void) {
        completion(SplitXEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SplitXEntry>) -> Void) {
        completion(Timeline(entries: [SplitXEntry(date: Date())], policy: .never))
    }
}

/// Renders the complication for each accessory family a watch face can host.
struct SplitXComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            // Round slot on the face: the add glyph, tinted by the face.
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
            }
            .widgetAccentable()

        case .accessoryCorner:
            // Curved corner slot.
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .widgetAccentable()
                .widgetLabel("SplitX")

        case .accessoryInline:
            // Single line of text beside the time.
            Label("SplitX", systemImage: "plus.circle.fill")

        case .accessoryRectangular:
            // Wide slot: name plus a hint at what the tap does.
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text("SplitX").font(.headline)
                    Text("Add an expense").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

        @unknown default:
            Image(systemName: "plus.circle.fill")
                .widgetAccentable()
        }
    }
}

struct SplitXComplication: Widget {
    let kind = "SplitXComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SplitXProvider()) { _ in
            SplitXComplicationView()
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("SplitX")
        .description("Open SplitX to add an expense.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

@main
struct SplitXComplicationBundle: WidgetBundle {
    var body: some Widget {
        SplitXComplication()
    }
}

#Preview("Circular", as: .accessoryCircular) {
    SplitXComplication()
} timeline: {
    SplitXEntry(date: .now)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    SplitXComplication()
} timeline: {
    SplitXEntry(date: .now)
}
