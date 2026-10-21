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
        // One container, so the bar and its caveat are one piece of glass that merges
        // and separates as the caveat comes and goes.
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                // Every number here is the scene's own, so the bar describes what is on
                // the globe. Scrub the replay back and these follow it; they are not the
                // whole-log figures from the Stats screen, which would quietly disagree
                // with the picture underneath them.
                // Four across where they fit; two by two at large text sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) { items }
                    Grid(horizontalSpacing: 18, verticalSpacing: 6) {
                        GridRow { items.prefix }
                        GridRow { items.suffix }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .rect(cornerRadius: 26))

                if let caveat {
                    CaveatLabel(text: caveat)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                        .padding(.horizontal, 24)
                }
            }
        }
        .padding(.top, 8)
    }

    private var items: SummaryItems {
        SummaryItems(
            first: [
                (value: "\(countries)", label: countries == 1 ? "country" : "countries"),
                (value: distance, label: "travelled"),
            ],
            second: [
                (value: "\(places)", label: places == 1 ? "place" : "places"),
                (value: "\(scene.arcs.count)", label: scene.arcs.count == 1 ? "leg" : "legs"),
            ]
        )
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

    /// The four figures, in two halves so a narrow screen can stack them two by two.
    private struct SummaryItems: View {
        let first: [(value: String, label: String)]
        let second: [(value: String, label: String)]

        var body: some View {
            row(first)
            row(second)
        }

        var prefix: some View {
            row(first)
        }

        var suffix: some View {
            row(second)
        }

        private func row(_ figures: [(value: String, label: String)]) -> some View {
            ForEach(figures, id: \.label) { figure in
                VStack(spacing: 0) {
                    Text(figure.value)
                        .font(.system(.subheadline, design: .rounded, weight: .bold)
                            .monospacedDigit())
                        .contentTransition(.numericText())
                    Text(figure.label).font(.caption2).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
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

/// The replay (§9): play it through, or scrub it by hand.
///
/// Stops on days something happened rather than running continuously, so it steps from
/// trip to trip instead of crawling through empty years. Played, it walks the stops at
/// a pace that fits the whole log into about fifteen seconds.
struct GlobeTimelineBar: View {
    let timeline: GlobeTimeline
    @Binding var replayIndex: Double?
    let onScrubToDate: () -> Void

    @State private var isPlaying = false

    var body: some View {
        if timeline.stops.count > 1 {
            // What the replay cannot place is said once, in the summary bar above, which
            // follows the replay.
            HStack(spacing: 10) {
                playButton
                slider
                Text(label)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                if replayIndex != nil {
                    Button("Show Everything", systemImage: "xmark") {
                        isPlaying = false
                        replayIndex = nil
                    }
                    .labelStyle(.iconOnly)
                    .font(.footnote.weight(.semibold))
                    .frame(width: 32, height: 44)
                    .contentShape(.rect)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .glassEffect(.regular, in: .capsule)
            .task(id: isPlaying) { await play() }
            .onChange(of: timeline.stops.count) { isPlaying = false }
        }
    }

    private var lastIndex: Int {
        max(0, timeline.stops.count - 1)
    }

    private var playButton: some View {
        Button {
            isPlaying.toggle()
        } label: {
            Label(
                isPlaying ? "Pause Replay" : "Play Replay",
                systemImage: isPlaying ? "pause.fill" : "play.fill"
            )
            .labelStyle(.iconOnly)
            .font(.body)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 44, height: 44)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }

    /// Steps through the stops while playing. Starting from the end, or from the whole
    /// log, starts again from the first stop.
    private func play() async {
        guard isPlaying else { return }
        if replayIndex.map({ Int($0.rounded()) >= lastIndex }) ?? true {
            replayIndex = 0
            onScrubToDate()
        }
        let pause = Duration.seconds(min(1.2, max(0.35, 15 / Double(timeline.stops.count))))
        while let index = replayIndex, Int(index.rounded()) < lastIndex {
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled, isPlaying else { return }
            replayIndex = index.rounded() + 1
            onScrubToDate()
        }
        isPlaying = false
    }

    private var slider: some View {
        Slider(
            value: Binding(
                get: { replayIndex ?? Double(lastIndex) },
                set: { newValue in
                    isPlaying = false
                    replayIndex = newValue
                    onScrubToDate()
                }
            ),
            in: 0 ... Double(lastIndex),
            step: 1
        )
        .controlSize(.small)
        .accessibilityLabel("Replay position")
        .accessibilityValue(label)
        // A tick for each day the replay stops on.
        .sensoryFeedback(.selection, trigger: replayIndex)
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
        return Format.day(date)
    }
}

/// Standard or satellite (D-26), as a menu like a map's style picker.
struct GlobeStyleMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(GlobeImageryStore.self) private var imagery: GlobeImageryStore?

    var body: some View {
        @Bindable var model = model
        if imagery?.isAvailable ?? false {
            Menu {
                Picker("Globe Style", selection: $model.globeStyle) {
                    ForEach(GlobeStyle.allCases) { style in
                        Label(style.displayName, systemImage: style.symbolName).tag(style)
                    }
                }
                .pickerStyle(.inline)
                if model.globeStyle == .satellite {
                    Section {
                        Text("Blue Marble imagery: NASA Earth Observatory")
                    }
                }
            } label: {
                Label("Globe Style", systemImage: "map")
            }
        }
    }
}

/// Year, trip and mode filters (§9).
struct GlobeFilterMenu: View {
    @Environment(AppModel.self) private var model
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
                        Text(trip.displayName(model: model)).tag(UUID?.some(trip.id))
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
