import AntipodesCore
import AntipodesGlobe
import SwiftUI

/// Headline numbers across the top of the globe, with whatever the globe could not draw
/// spelled out underneath.
///
/// The caveat is on the screen rather than hidden, for the same reason every stat
/// carries one: a place quietly missing from the map is worse than a map that admits
/// what it is missing (R-CALC-5).
struct GlobeSummaryBar: View {
    let scene: GlobeScene
    let model: AppModel

    var body: some View {
        VStack(spacing: 6) {
            // Every number here is the scene's own, so the bar describes what is on
            // the globe. Scrub the replay back and these follow it; they are not the
            // whole-log figures from the Stats screen, which would quietly disagree
            // with the picture underneath them.
            HStack(spacing: 16) {
                item("\(scene.shadedCountryCodes.count)", label: "countries")
                item(distance, label: "travelled")
                item("\(places)", label: "places")
                item("\(scene.arcs.count)", label: "journeys")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: .capsule)

            if let caveat {
                CaveatLabel(text: caveat)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: .rect(cornerRadius: 9))
            }
        }
        .padding(.top, 8)
    }

    /// Wishlist pins are places the user has *not* been, so they are not counted here.
    private var places: Int {
        scene.pins.filter { $0.style != .wishlist }.count
    }

    private var distance: String {
        let value = model.rules.unitSystem.distance(fromKilometres: scene.totalDistanceKm)
        return "\(Int(value.rounded())) \(model.rules.unitSystem.distanceUnitAbbreviation)"
    }

    private func item(_ value: String, label: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.subheadline.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// The pins, arcs and shading caveats joined into one line, so the globe does not
    /// grow three separate warnings.
    private var caveat: String? {
        let parts = [
            scene.pinSummary.caveat.map { "Places: \($0)" },
            scene.arcSummary.caveat.map { "Journeys: \($0)" },
            scene.shadingSummary.caveat.map { "Shading: \($0)" },
        ].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// The replay scrubber (§9).
///
/// Stops on days something happened rather than running continuously, so dragging it
/// steps from trip to trip instead of crawling through empty years.
struct GlobeTimelineBar: View {
    let timeline: GlobeTimeline
    @Binding var replayIndex: Double?
    let onScrubToDate: () -> Void

    var body: some View {
        if timeline.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                header
                slider
                if let caveat = timeline.caveat {
                    Text(caveat)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: .rect(cornerRadius: 14))
        }
    }

    private var header: some View {
        HStack {
            Button {
                replayIndex = replayIndex == nil ? Double(max(0, timeline.stops.count - 1)) : nil
            } label: {
                Label(
                    replayIndex == nil ? "Replay" : "Show everything",
                    systemImage: replayIndex == nil ? "play.circle" : "globe"
                )
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(label)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var slider: some View {
        if timeline.stops.count > 1 {
            Slider(
                value: Binding(
                    get: { replayIndex ?? Double(timeline.stops.count - 1) },
                    set: { newValue in
                        replayIndex = newValue
                        onScrubToDate()
                    }
                ),
                in: 0 ... Double(timeline.stops.count - 1),
                step: 1
            )
            .controlSize(.small)
            .accessibilityLabel("Replay position")
            .accessibilityValue(label)
        }
    }

    private var label: String {
        guard let replayIndex,
              let date = timeline.date(atIndex: Int(replayIndex.rounded()))
        else {
            if let earliest = timeline.earliest, let latest = timeline.latest {
                return earliest.year == latest.year
                    ? "\(earliest.year)"
                    : "\(earliest.year)–\(latest.year)"
            }
            return "All time"
        }
        return date.iso
    }
}

/// Year, trip and mode filters (§9).
struct GlobeFilterMenu: View {
    @Binding var filter: GlobeFilter
    let years: [Int]
    let trips: [Trip]
    let modes: [TravelMode]

    var body: some View {
        Menu {
            Picker("Year", selection: $filter.year) {
                Text("All years").tag(Int?.none)
                ForEach(years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
            }

            if !trips.isEmpty {
                Picker("Trip", selection: $filter.tripID) {
                    Text("All trips").tag(UUID?.none)
                    ForEach(trips) { trip in
                        Text(trip.name ?? "Untitled trip").tag(UUID?.some(trip.id))
                    }
                }
            }

            if !modes.isEmpty {
                Picker("Mode", selection: $filter.mode) {
                    Text("All modes").tag(TravelMode?.none)
                    ForEach(modes) { mode in
                        Label(mode.displayName, systemImage: mode.symbolName)
                            .tag(TravelMode?.some(mode))
                    }
                }
            }

            if filter.isFiltering {
                Divider()
                Button("Clear filters", systemImage: "xmark.circle") {
                    filter = GlobeFilter(replayUpTo: filter.replayUpTo)
                }
            }
        } label: {
            Label(
                "Filter",
                systemImage: filter.isFiltering
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
    }
}

/// What a tap on a pin or an arc opens (§9).
struct GlobeSelectionSheet: View {
    let selection: GlobeSelection
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                switch selection {
                case let .pin(pin): pinDetail(pin)
                case let .arc(arc): arcDetail(arc)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var title: String {
        switch selection {
        case let .pin(pin): pin.place.name
        case let .arc(arc): arc.title
        }
    }

    @ViewBuilder
    private func pinDetail(_ pin: GlobePin) -> some View {
        Section {
            row("Kind", pin.place.kind.displayName)
            if let visitType = pin.visitType {
                row("Visit", visitType.displayName)
                Text(visitType.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if pin.style == .wishlist {
                row("Status", "On your wishlist")
            }
            if pin.date.isKnown {
                row("Date", pin.date.exportString)
            } else {
                row("Date", "Not recorded")
            }
        }
        if let country = pin.place.countryName {
            Section("Where") {
                row("Country", country)
                if let region = pin.place.regionName {
                    row("Region", region)
                }
                if let city = pin.place.cityName, city != pin.place.name {
                    row("City", city)
                }
            }
        }
    }

    @ViewBuilder
    private func arcDetail(_ arc: GlobeArc) -> some View {
        Section {
            Label(arc.mode.displayName, systemImage: arc.mode.symbolName)
            row("From", arc.origin.name)
            row("To", arc.destination.name)
            row("Date", arc.date.isKnown ? arc.date.exportString : "Not recorded")
        }
        Section("Distance") {
            row("Distance", distanceText(for: arc))
            Text(arc.mode.pathSourceDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Read off the leg in the log, never recomputed here: the one implementation of
    /// distance lives in `AntipodesCore.GreatCircle` (AGENTS.md §7).
    private func distanceText(for arc: GlobeArc) -> String {
        guard let leg = model.log.allLegs.first(where: { $0.id == arc.id }) else {
            return "Unknown"
        }
        let distance = leg.distance
        let converted = model.rules.unitSystem.distance(fromKilometres: distance.kilometres)
        let unit = model.rules.unitSystem.distanceUnitAbbreviation
        let formatted = "\(Int(converted.rounded())) \(unit)"
        return distance.source.isApproximate ? "\(formatted) (approximate)" : formatted
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
