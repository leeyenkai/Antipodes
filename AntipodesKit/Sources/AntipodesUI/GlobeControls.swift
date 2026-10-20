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
    @Environment(AppModel.self) private var model
    let scene: GlobeScene

    var body: some View {
        VStack(spacing: 8) {
            // Every number here is the scene's own, so the bar describes what is on
            // the globe. Scrub the replay back and these follow it; they are not the
            // whole-log figures from the Stats screen, which would quietly disagree
            // with the picture underneath them.
            HStack(spacing: 18) {
                item("\(countries)", label: countries == 1 ? "country" : "countries")
                item(distance, label: "travelled")
                item("\(places)", label: places == 1 ? "place" : "places")
                item("\(scene.arcs.count)", label: scene.arcs.count == 1 ? "leg" : "legs")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)

            if let caveat {
                CaveatLabel(text: caveat)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    .padding(.horizontal, 24)
            }
        }
        .padding(.top, 8)
    }

    /// Shaded countries on the list the user counts (Q-4), so this agrees with the
    /// headline on the Stats screen; land off the list is still shaded, just not counted.
    private var countries: Int {
        let facts = model.catalogue.countries
        guard !facts.isEmpty else { return scene.shadedCountryCodes.count }
        return scene.shadedCountryCodes
            .count { facts[$0]?.isCounted(on: model.rules.countryList) ?? false }
    }

    /// Wishlist pins and the home markers are not places the user has been.
    private var places: Int {
        scene.pins.filter(\.style.isTravel).count
    }

    private var distance: String {
        Format.distance(scene.totalDistanceKm, model.rules.unitSystem)
    }

    private func item(_ value: String, label: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                .contentTransition(.numericText())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
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
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
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

/// What a tap on a pin or an arc opens on iPhone (§9): the record in a sheet over the
/// globe. The record's own form supplies Cancel and Save; a marker supplies Close.
struct GlobeSelectionSheet: View {
    let selection: GlobeSelection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GlobeSelectionDetail(selection: selection) { dismiss() }
                .environment(\.editorPlacement, .root)
                .logDestinations()
        }
        .presentationDetents([.medium, .large])
    }
}

/// The same, on iPad and Mac: in an inspector beside the globe, which stays in view and
/// can be turned while the record is open (R-PLAT-2, R-NAV-1).
struct GlobeSelectionInspector: View {
    let selection: GlobeSelection
    let close: () -> Void

    var body: some View {
        NavigationStack {
            GlobeSelectionDetail(selection: selection, close: close)
                .environment(\.editorPlacement, .root)
                .logDestinations()
        }
        // A new tap is a new record: start its form afresh. The globe asks before
        // replacing a form with unsaved edits (`UnsavedEditsKey`).
        .id(selection.id)
    }
}

/// The record a tap landed on, ready to edit.
struct GlobeSelectionDetail: View {
    let selection: GlobeSelection
    /// Closes whatever is showing this: the sheet, or the inspector.
    let close: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.deferredAdd) private var deferredAdd

    var body: some View {
        switch selection {
        case let .pin(pin):
            switch pin.style {
            case .visited, .notCounted:
                if let visit = model.log.visits.first(where: { $0.id == pin.id }) {
                    VisitForm(place: visit.place, existing: visit, onDone: close)
                } else {
                    markerDetail(pin)
                }
            case .wishlist, .home, .antipode:
                markerDetail(pin)
            }
        case let .arc(arc):
            if let journey = model.log.journeys
                .first(where: { $0.legs.contains { $0.id == arc.id } }) {
                JourneyEditor(existing: journey, onDone: close)
            } else {
                ContentUnavailableView("Journey not found", systemImage: "questionmark")
            }
        }
    }

    private func markerDetail(_ pin: GlobePin) -> some View {
        List {
            Section {
                PlaceHeader(place: pin.place)
            }
            switch pin.style {
            case .wishlist:
                Section {
                    Button("Log a Visit", systemImage: "plus") {
                        let request = AddRequest(start: .place(pin.place))
                        if let deferredAdd {
                            deferredAdd(request)
                        } else {
                            close()
                            model.addRequest = request
                        }
                    }
                    Button("Remove from Wishlist", systemImage: "star.slash", role: .destructive) {
                        model.removeFromWishlist(place: pin.place)
                        close()
                    }
                } footer: {
                    Text("On your wishlist. It ticks itself off when you log a visit here.")
                }
            case .home:
                Section {
                    Text("Home. Your antipode is the dashed ring on the far side of the globe.")
                        .foregroundStyle(.secondary)
                }
            case .antipode:
                Section {
                    Text("""
                    The point on exactly the other side of the Earth from \(model.home?
                        .name ?? "home"). \
                    \(antipodeLine)
                    """)
                    .foregroundStyle(.secondary)
                }
            case .visited, .notCounted:
                EmptyView()
            }
        }
        .navigationTitle(pin.place.name)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: close)
            }
        }
    }

    private var antipodeLine: String {
        let extremes = model.statistics.extremes
        guard let nearest = extremes.nearestToAntipodeOfHome,
              let gap = extremes.nearestToAntipodeKm else {
            return "Log places to see how close you've been."
        }
        return """
        The closest you've been is \(nearest.place.name), \
        \(Format.distance(gap, model.rules.unitSystem)) away.
        """
    }
}
