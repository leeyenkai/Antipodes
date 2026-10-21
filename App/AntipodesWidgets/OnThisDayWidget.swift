import AntipodesCore
import SwiftUI
import WidgetKit

// MARK: - On this day

struct OnThisDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "on-this-day", provider: SnapshotProvider()) { entry in
            OnThisDayView(entry: entry)
        }
        .configurationDisplayName("On This Day")
        .description("Where you were on this date in earlier years.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct OnThisDayView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        let day = CalendarDate(entry.date) ?? .today()
        let memories = entry.snapshot.memories(on: day)
        if family == .accessoryRectangular {
            lockScreen(memories, day: day)
        } else {
            homeScreen(memories, day: day)
        }
    }

    /// The Lock Screen: one memory, in the system's own monochrome.
    private func lockScreen(_ memories: [WidgetSnapshot.Memory], day: CalendarDate) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("On this day", systemImage: "clock.arrow.circlepath")
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            if let memory = memories.first {
                Text(memory.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(Self.yearsAgo(memory.yearsAgo(on: day)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Nothing logged on this date yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(memories.first?.link ?? DeepLink.trips.url)
    }

    private func homeScreen(_ memories: [WidgetSnapshot.Memory], day: CalendarDate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("On this day", systemImage: "clock.arrow.circlepath")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetPalette.visited)
            if memories.isEmpty {
                Spacer(minLength: 0)
                Text("Nothing logged on this date — yet.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 0)
            } else {
                ForEach(
                    Array(memories.prefix(family == .systemSmall ? 2 : 3).enumerated()),
                    id: \.offset
                ) { _, memory in
                    // Each memory opens its own record; a small widget takes only one
                    // tap target, so there the first memory stands for the widget.
                    Link(destination: memory.link ?? DeepLink.trips.url) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(memory.title)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(
                                "\(memory.subtitle) · \(Self.yearsAgo(memory.yearsAgo(on: day)))"
                            )
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
        .containerBackground(for: .widget) { WidgetPalette.sky }
        .widgetURL(memories.first?.link ?? DeepLink.trips.url)
    }

    private static func yearsAgo(_ years: Int) -> String {
        years == 1 ? "1 year ago" : "\(years) years ago"
    }
}
