import AntipodesCore
import AppIntents
import SwiftUI
import WidgetKit

// Home and Lock Screen widgets (R-SHARE-2).
//
// Widgets read a small snapshot the app writes into the shared app-group container
// whenever the log changes (`WidgetSnapshot`). They never open the log or the place
// database themselves, and nothing here touches the network.

@main
struct AntipodesWidgets: WidgetBundle {
    var body: some Widget {
        CountriesWidget()
        GlobeWidget()
        OnThisDayWidget()
        CollectionWidget()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let isPlaceholder: Bool
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in _: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(Self.entry(preview: context.isPreview))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // The app reloads the timeline whenever the log changes; this only refreshes at
        // midnight, when "on this day" moves on.
        completion(Timeline(
            entries: [Self.entry(preview: false)],
            policy: .after(Self.nextMidnight)
        ))
    }

    static func entry(preview: Bool) -> SnapshotEntry {
        if let snapshot = WidgetSnapshot.load() {
            return SnapshotEntry(date: .now, snapshot: snapshot, isPlaceholder: false)
        }
        return SnapshotEntry(date: .now, snapshot: .placeholder, isPlaceholder: !preview)
    }

    static var nextMidnight: Date {
        Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 1),
            matchingPolicy: .nextTime
        ) ?? .now.addingTimeInterval(6 * 3600)
    }
}

private enum WidgetPalette {
    static let visited = Color(red: 0.31, green: 0.78, blue: 0.62)
    static let sky = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.11, blue: 0.18),
            Color(red: 0.01, green: 0.02, blue: 0.05),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Countries

struct CountriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "countries", provider: SnapshotProvider()) { entry in
            CountriesView(entry: entry)
        }
        .configurationDisplayName("Countries")
        .description("How many countries you've been to, and your share of the world.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

private struct CountriesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        let snapshot = entry.snapshot
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: min(1, snapshot.worldPercent / 100)) {
                    Image(systemName: "globe")
                } currentValueLabel: {
                    Text("\(snapshot.countries)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label("\(snapshot.countries) countries", systemImage: "globe")
                        .font(.headline)
                    Text("\(percent(snapshot.worldPercent)) of the world")
                    Text("\(snapshot.continents) of 7 continents")
                        .foregroundStyle(.secondary)
                }
            case .accessoryInline:
                Label(
                    "\(snapshot.countries) countries · \(percent(snapshot.worldPercent))",
                    systemImage: "globe"
                )
            case .systemMedium:
                HStack(spacing: 16) {
                    GlobeImage()
                        .frame(width: 120, height: 120)
                    stack(snapshot)
                }
            default:
                stack(snapshot)
            }
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
        .containerBackground(for: .widget) { WidgetPalette.sky }
    }

    private func stack(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "globe.europe.africa.fill")
                .foregroundStyle(WidgetPalette.visited)
            Spacer(minLength: 0)
            Text("\(snapshot.countries)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .foregroundStyle(.white)
            Text("countries")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            ProgressView(value: min(1, snapshot.worldPercent / 100))
                .tint(WidgetPalette.visited)
            Text("\(percent(snapshot.worldPercent)) of \(snapshot.countryListName)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(1)))
    }
}

// MARK: - Globe

struct GlobeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "globe", provider: SnapshotProvider()) { entry in
            GlobeWidgetView(entry: entry)
        }
        .configurationDisplayName("Globe")
        .description("Your globe, with every country you've been to shaded.")
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

private struct GlobeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        let snapshot = entry.snapshot
        VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 6) {
            GlobeImage()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if family == .systemLarge {
                HStack(alignment: .firstTextBaseline) {
                    figure("\(snapshot.countries)", "countries")
                    Spacer()
                    figure("\(snapshot.continents)", "continents")
                    Spacer()
                    figure(snapshot.distanceText, "travelled")
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(snapshot.countries)")
                        .font(.headline)
                        .fontDesign(.rounded)
                    Text("countries")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .foregroundStyle(.white)
            }
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
        .containerBackground(for: .widget) { WidgetPalette.sky }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

/// The globe the app rendered last, or a plain one before it has.
private struct GlobeImage: View {
    var body: some View {
        if let url = WidgetSnapshot.containerURL()?.appending(path: WidgetSnapshot.globeImageName),
           let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "globe.europe.africa.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(WidgetPalette.visited.opacity(0.6))
                .padding(12)
        }
    }
}

// MARK: - On this day

struct OnThisDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "on-this-day", provider: SnapshotProvider()) { entry in
            OnThisDayView(entry: entry)
        }
        .configurationDisplayName("On This Day")
        .description("Where you were on this date in earlier years.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct OnThisDayView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        let memories = entry.snapshot.memoriesDay == today ? entry.snapshot.memories : []
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
                    VStack(alignment: .leading, spacing: 0) {
                        Text(memory.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(
                            "\(memory.subtitle) · \(Self.yearsAgo(memory.yearsAgo))"
                        )
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
        .containerBackground(for: .widget) { WidgetPalette.sky }
    }

    private var today: String {
        CalendarDate.today().iso
    }

    private static func yearsAgo(_ years: Int) -> String {
        years == 1 ? "1 year ago" : "\(years) years ago"
    }
}

// MARK: - Collection progress

struct CollectionChoice: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Collection"
    static let defaultQuery = CollectionQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct CollectionQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CollectionChoice] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CollectionChoice] {
        (WidgetSnapshot.load() ?? .placeholder).collections.map { CollectionChoice(
            id: $0.id,
            name: $0.name
        ) }
    }

    func defaultResult() async -> CollectionChoice? {
        let collections = (WidgetSnapshot.load() ?? .placeholder).collections
        return collections.furthestThrough.map { CollectionChoice(id: $0.id, name: $0.name) }
    }
}

struct SelectCollectionIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Collection"
    static let description = IntentDescription("Choose which collection to track.")

    @Parameter(title: "Collection")
    var collection: CollectionChoice?
}

struct CollectionEntry: TimelineEntry {
    let date: Date
    let collection: WidgetSnapshot.CollectionSummary?
    let isPlaceholder: Bool
}

struct CollectionProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> CollectionEntry {
        CollectionEntry(
            date: .now,
            collection: WidgetSnapshot.placeholder.collections.first,
            isPlaceholder: true
        )
    }

    func snapshot(
        for configuration: SelectCollectionIntent,
        in _: Context
    ) async -> CollectionEntry {
        entry(for: configuration)
    }

    func timeline(
        for configuration: SelectCollectionIntent,
        in _: Context
    ) async -> Timeline<CollectionEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    private func entry(for configuration: SelectCollectionIntent) -> CollectionEntry {
        let collections = (WidgetSnapshot.load() ?? .placeholder).collections
        let chosen = collections.first { $0.id == configuration.collection?.id } ?? collections
            .furthestThrough
        return CollectionEntry(date: .now, collection: chosen, isPlaceholder: false)
    }
}

extension [WidgetSnapshot.CollectionSummary] {
    /// Until the user picks one, the collection they are furthest through: the one
    /// they are most likely to want to finish.
    var furthestThrough: WidgetSnapshot.CollectionSummary? {
        self.max { first, second in
            let a = first.total == 0 ? 0 : Double(first.visited) / Double(first.total)
            let b = second.total == 0 ? 0 : Double(second.visited) / Double(second.total)
            return a < b
        }
    }
}

struct CollectionWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "collection",
            intent: SelectCollectionIntent.self,
            provider: CollectionProvider()
        ) { entry in
            CollectionView(entry: entry)
        }
        .configurationDisplayName("Collection")
        .description("Progress through a collection, such as the Nordic capitals.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

private struct CollectionView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CollectionEntry

    var body: some View {
        Group {
            if let collection = entry.collection {
                let fraction = collection
                    .total == 0 ? 0 : Double(collection.visited) / Double(collection.total)
                if family == .accessoryCircular {
                    Gauge(value: fraction) {
                        Image(systemName: collection.symbol ?? "square.stack.3d.up")
                    } currentValueLabel: {
                        Text("\(collection.visited)")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: collection.symbol ?? "square.stack.3d.up")
                                .foregroundStyle(WidgetPalette.visited)
                            Spacer()
                            Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer(minLength: 0)
                        Text(collection.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text("\(collection.visited) of \(collection.total)")
                            .font(.title2.weight(.bold))
                            .fontDesign(.rounded)
                            .foregroundStyle(.white)
                        ProgressView(value: fraction)
                            .tint(WidgetPalette.visited)
                    }
                }
            } else {
                Text("Open Antipodes to load your collections.")
                    .font(.caption)
                    .foregroundStyle(.white)
            }
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
        .containerBackground(for: .widget) { WidgetPalette.sky }
    }
}
