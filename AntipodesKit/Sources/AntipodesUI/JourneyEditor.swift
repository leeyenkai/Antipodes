import AntipodesCore
import SwiftUI

/// Logs a new journey or edits an existing one, leg by leg (§5.3).
///
/// A quick leg is mode, origin, destination, date — about four taps after search
/// (R-JLOG-1). Detail lives behind a disclosure on each leg (R-LEG-2, R-JLOG-2). "Add a
/// connecting leg" starts the next one where the last ended, and the time between them
/// shows as a connection that can be marked missed (R-JLOG-4).
struct JourneyEditor: View {
    @Environment(AppModel.self) private var model

    let existing: Journey?
    let onDone: () -> Void
    /// The date a new journey's first leg starts on, when it is not today.
    let startDate: FlexibleDate?

    @State private var legs: [LegDraft]
    @State private var expandedLeg: UUID?
    @State private var title: String
    @State private var tripID: UUID?
    @State private var newTripName: String?
    /// Where a new journey arrived, to log as a stay so it counts (D-32), and whether to.
    @State private var arrivals: [Arrival] = []
    @State private var logsArrivals = true
    @State private var isConfirmingDelete = false
    @State private var saved = false
    /// What the editor held when it opened, so it knows whether there is anything to
    /// lose by leaving.
    @State private var baseline: Fields

    struct Fields: Equatable {
        var legs: [LegDraft]
        var title: String
        var tripID: UUID?
    }

    /// Which leg's end is being chosen. One picker for the whole form: a `.sheet` on a
    /// `Section` is applied to every row in it, and competing sheets tear down the
    /// sheet this editor is itself presented in.
    @State private var picking: EndpointRequest?
    /// The end to ask for once the current picker has gone: a new leg's To follows its
    /// From, so a quick leg is mode, from, to, save (R-JLOG-1).
    @State private var nextPick: EndpointRequest?
    @State private var hasAskedForFirstEnd = false
    /// The leg whose transit line and stops are being chosen (R-JLOG-5).
    @State private var pickingTransit: TransitPick?

    struct TransitPick: Identifiable {
        let id: UUID
    }

    struct EndpointRequest: Identifiable {
        let legID: UUID
        let end: LegEnd

        var id: String {
            "\(legID.uuidString)-\(end.rawValue)"
        }
    }

    init(
        existing: Journey? = nil,
        start: AddRequest.Start = .journey(nil),
        tripID: UUID? = nil,
        date: FlexibleDate? = nil,
        onDone: @escaping () -> Void
    ) {
        self.existing = existing
        self.onDone = onDone
        startDate = date
        var drafts: [LegDraft] = []
        if let existing {
            drafts = existing.legs.map(LegDraft.init(leg:))
        } else {
            switch start {
            case let .route(route): drafts = [LegDraft(route: route)]
            case let .journey(mode?): drafts = [LegDraft(mode: mode)]
            default: drafts = []
            }
            if let date {
                for index in drafts.indices {
                    drafts[index].date = date
                }
            }
        }
        _legs = State(initialValue: drafts)
        _expandedLeg = State(initialValue: drafts.count == 1 ? drafts.first?.id : nil)
        _title = State(initialValue: existing?.title ?? "")
        _tripID = State(initialValue: existing?.tripID ?? tripID)
        _baseline = State(initialValue: Fields(
            legs: drafts,
            title: existing?.title ?? "",
            tripID: existing?.tripID ?? tripID
        ))
    }

    var body: some View {
        Form {
            if legs.isEmpty {
                Section {
                    ModeGrid { mode in
                        var draft = LegDraft(mode: mode)
                        if let startDate {
                            draft.date = startDate
                        }
                        legs = [draft]
                        expandedLeg = draft.id
                        askForFirstEnd(of: draft)
                    }
                } header: {
                    Text("How did you travel?")
                } footer: {
                    Text(
                        """
                        Pick the first leg's mode. A journey can mix modes — fly, then take the \
                        train.
                        """
                    )
                }
                if existing == nil {
                    RecentRides(tripID: tripID, onDone: onDone)
                }
            }

            ForEach($legs) { $leg in
                let index = legs.firstIndex { $0.id == leg.id } ?? 0
                if index > 0 {
                    ConnectionRow(previous: legs[index - 1], next: $leg)
                }
                LegSection(
                    draft: $leg,
                    number: index + 1,
                    isOnly: legs.count == 1,
                    isExpanded: expandedLeg == leg.id,
                    expand: { expandedLeg = expandedLeg == leg.id ? nil : leg.id },
                    remove: { remove(leg.id) },
                    pick: { end in picking = EndpointRequest(legID: leg.id, end: end) },
                    pickTransit: { pickingTransit = TransitPick(id: leg.id) }
                )
            }

            if let last = legs.last {
                Section {
                    // A connection is often a change of mode — land, then take the train —
                    // so the next leg's mode is the first question, the last one's first.
                    Menu {
                        ForEach([last.mode] + TravelMode.loggable
                            .filter { $0 != last.mode }) { mode in
                                Button(mode.displayName, systemImage: mode.symbolName) {
                                    addConnectingLeg(after: last, by: mode)
                                }
                            }
                    } label: {
                        Label("Add Connecting Leg", systemImage: "plus.circle.fill")
                    }
                    .disabled(!last.isComplete)
                }

                Section("Journey") {
                    TextField("Title (optional)", text: $title)
                    TripPicker(selection: $tripID, newTripName: $newTripName)
                }

                if existing == nil, !arrivals.isEmpty {
                    ArrivalSection(arrivals: arrivals, isOn: $logsArrivals)
                }
            }

            if let existing {
                Section {
                    if existing.legs.count == 1, let leg = existing.legs.first {
                        Button("Ride Again Today", systemImage: "arrow.uturn.forward") {
                            model.rideAgain(leg, tripID: existing.tripID)
                            onDone()
                        }
                    } else {
                        // Any one leg of a longer journey: the commuter's second train.
                        Menu {
                            ForEach(existing.legs) { leg in
                                Button(
                                    "\(leg.origin.shortName) → \(leg.destination.shortName)",
                                    systemImage: leg.mode.symbolName
                                ) {
                                    model.rideAgain(leg, tripID: existing.tripID)
                                    onDone()
                                }
                            }
                        } label: {
                            Label("Ride a Leg Again Today", systemImage: "arrow.uturn.forward")
                        }
                    }
                    Button("Delete Journey", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
        }
        .task(id: existing == nil ? legs.compactMap(\.leg) : []) {
            guard existing == nil else { return }
            arrivals = await model.arrivals(for: legs.compactMap(\.leg))
        }
        .navigationTitle(existing == nil ? "Log Journey" : "Edit Journey")
        // Ready by the time both ends are picked, so the leg is measured along its
        // railway, roads or ferry route straight away (D-30).
        .task { await model.preloadTrackNetworks() }
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(existing == nil ? "Save" : "Done", systemImage: "checkmark", action: save)
                    .disabled(legs.isEmpty || !legs.allSatisfy(\.isComplete))
            }
            // A catalogue route opened from search can be saved for later instead of
            // logged (R-WISH-1): search offers no wishlist swipe on a route, so here.
            if existing == nil, let route = catalogueRoute {
                ToolbarItem(placement: .primaryAction) {
                    let isOn = model.isOnWishlist(routeID: route.id)
                    Button(
                        isOn ? "Remove from Wishlist" : "Add to Wishlist",
                        systemImage: isOn ? "star.fill" : "star"
                    ) {
                        if isOn {
                            model.removeFromWishlist(
                                model.log.wishlist.filter { $0.routeID == route.id }.map(\.id)
                            )
                        } else {
                            model.addToWishlist(route: route)
                        }
                    }
                    .tint(Palette.wishlist)
                }
            }
        }
        .onAppear {
            // A new journey that already knows its mode starts at "From?", not at a form.
            guard existing == nil, !hasAskedForFirstEnd, legs.count == 1,
                  let first = legs.first, first.origin == nil else { return }
            hasAskedForFirstEnd = true
            askForFirstEnd(of: first)
        }
        .guardingUnsavedEdits(
            Fields(legs: legs, title: title, tripID: tripID) != baseline && !saved,
            discard: onDone
        )
        .sensoryFeedback(.success, trigger: saved)
        // Either sheet can hand over to the place picker once it has gone: one sheet
        // cannot open over another that is still leaving.
        .sheet(item: $pickingTransit, onDismiss: openNextPick) { pick in
            TransitRidePicker { ride in
                if let index = legs.firstIndex(where: { $0.id == pick.id }) {
                    legs[index].apply(ride)
                }
            } onPlacesInstead: {
                nextPick = EndpointRequest(legID: pick.id, end: .origin)
            }
        }
        .sheet(item: $picking, onDismiss: openNextPick) { request in
            endpointPicker(request)
        }
        .confirmationDialog(
            "Delete this journey?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Journey", role: .destructive) {
                if let existing {
                    model.deleteJourneys([existing.id])
                }
                onDone()
            }
        } message: {
            Text(
                "Every leg is removed from your log and your statistics."
                    + " You can undo it straight afterwards."
            )
        }
    }

    @ViewBuilder
    private func endpointPicker(_ request: EndpointRequest) -> some View {
        if let index = legs.firstIndex(where: { $0.id == request.legID }) {
            let mode = legs[index].mode
            PlacePickerSheet(
                title: request.end == .origin ? "From" : "To",
                // The title hides while the search field has the keyboard, so the prompt
                // says which end this is too.
                prompt: endpointPrompt(request.end, mode),
                kinds: mode == .flight ? [.airport] : [.city, .landmark, .airport],
                fixedKinds: mode.endpointKinds,
                suggestions: endpointSuggestions(for: mode)
            ) { place in
                guard let index = legs.firstIndex(where: { $0.id == request.legID }) else { return }
                if request.end == .origin {
                    legs[index].origin = place
                    if legs[index].destination == nil {
                        nextPick = EndpointRequest(legID: request.legID, end: .destination)
                    }
                } else {
                    legs[index].destination = place
                }
                legs[index].leaveTransitLine()
                legs[index].endpointChanged(route: legs[index].routeID.flatMap(model.route(id:)))
                let draft = legs[index]
                let networks = model.trackNetworks
                Task {
                    let measured = await LegDraft.measured(draft, along: networks)
                    if let index = legs.firstIndex(where: { $0.id == draft.id }) {
                        legs[index].adoptMeasurement(measured, madeFrom: draft)
                    }
                }
            }
        }
    }

    private func addConnectingLeg(after last: LegDraft, by mode: TravelMode) {
        let next = last.connecting(by: mode)
        legs.append(next)
        expandedLeg = next.id
        if mode == .cityTransit {
            pickingTransit = TransitPick(id: next.id)
        } else if next.origin == nil {
            // A flight after a train: the airport it left from, then where it went.
            picking = EndpointRequest(legID: next.id, end: .origin)
        } else {
            // It starts where the last leg ended; where it goes is the question.
            picking = EndpointRequest(legID: next.id, end: .destination)
        }
    }

    /// The catalogue route a new journey of one leg rides, if it rides one.
    private var catalogueRoute: RouteInfo? {
        guard legs.count == 1 else { return nil }
        return legs.first?.routeID.flatMap(model.route(id:))
    }

    private func endpointPrompt(_ end: LegEnd, _ mode: TravelMode) -> String {
        "\(end == .origin ? "From" : "To"): search \(mode.endpointPluralNoun)"
    }

    private func openNextPick() {
        if let nextPick {
            picking = nextPick
            self.nextPick = nil
        }
    }

    /// A city transit ride starts at its line (R-JLOG-5); anything else at "From?".
    private func askForFirstEnd(of draft: LegDraft) {
        if draft.mode == .cityTransit {
            pickingTransit = TransitPick(id: draft.id)
        } else {
            picking = EndpointRequest(legID: draft.id, end: .origin)
        }
    }

    /// Home, then the ends of recent legs by the same mode, then — for anything but a
    /// flight — cities recently visited, then other legs' ends of the right kind: a
    /// train's suggestions are towns, not the airports of last year's flights.
    private func endpointSuggestions(for mode: TravelMode) -> [PlaceReference] {
        let legs = model.log.allLegs.reversed()
        let ends = { (legs: [JourneyLeg]) in legs.flatMap { [$0.destination, $0.origin] } }
        let fits = { (place: PlaceReference) in (place.kind == .airport) == (mode == .flight) }
        let sameMode = ends(legs.filter { $0.mode == mode }).filter { mode != .flight || fits($0) }
        let otherModes = ends(legs.filter { $0.mode != mode }).filter(fits)
        let home = mode == .flight ? [] : [model.home].compactMap(\.self)
        let visitedCities = mode == .flight ? [] : model.log.visits
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            .map(\.place)
            .filter { $0.kind == .city }
        var seen: Set<PlaceID> = []
        return Array((home + sameMode + visitedCities + otherModes)
            .filter { seen.insert($0.id).inserted }
            .prefix(8))
    }

    /// Removes a leg once any field in it has let go of the keyboard. A text field still
    /// editing a leg that has gone would write through a binding to an index that no
    /// longer exists.
    private func remove(_ id: UUID) {
        endEditing()
        Task { @MainActor in
            withAnimation {
                legs.removeAll { $0.id == id }
                if expandedLeg == id {
                    expandedLeg = legs.last?.id
                }
            }
        }
    }

    private func save() {
        let built = legs.compactMap(\.leg)
        guard built.count == legs.count, !built.isEmpty else { return }
        // Nothing changed: nothing to write, and nothing stale to write over.
        if existing != nil, Fields(legs: legs, title: title, tripID: tripID) == baseline {
            onDone()
            return
        }
        let tripID: UUID?
        do {
            tripID = try model.resolveTrip(self.tripID, newTripName: newTripName)
        } catch {
            model.errorMessage = AppModel.tripNotCreated(error)
            return
        }
        // Created now; a save that fails below and is tried again must not make another.
        self.tripID = tripID
        newTripName = nil
        if var journey = existing {
            let current = model.log.journeys.first { $0.id == journey.id }?.legs ?? []
            journey.legs = built.map { $0.keepingMeasurement(from: current) }
            journey.title = title.trimmedOrNil
            journey.tripID = tripID
            guard model.updateJourney(journey) else { return }
        } else {
            do {
                try model.logJourney(
                    legs: built,
                    tripID: tripID,
                    title: title,
                    arrivals: logsArrivals ? arrivals : []
                )
            } catch {
                model.errorMessage = error.localizedDescription
                return
            }
        }
        saved = true
        onDone()
    }
}
