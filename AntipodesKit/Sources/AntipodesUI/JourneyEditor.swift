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

    @State private var legs: [LegDraft]
    @State private var expandedLeg: UUID?
    @State private var title: String
    @State private var tripID: UUID?
    @State private var isConfirmingDelete = false
    @State private var saved = false
    /// Which leg's end is being chosen. One picker for the whole form: a `.sheet` on a
    /// `Section` is applied to every row in it, and competing sheets tear down the
    /// sheet this editor is itself presented in.
    @State private var picking: EndpointRequest?

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
        onDone: @escaping () -> Void
    ) {
        self.existing = existing
        self.onDone = onDone
        var drafts: [LegDraft] = []
        if let existing {
            drafts = existing.legs.map(LegDraft.init(leg:))
        } else {
            switch start {
            case let .route(route): drafts = [LegDraft(route: route)]
            case let .journey(mode?): drafts = [LegDraft(mode: mode)]
            default: drafts = []
            }
        }
        _legs = State(initialValue: drafts)
        _expandedLeg = State(initialValue: drafts.count == 1 ? drafts.first?.id : nil)
        _title = State(initialValue: existing?.title ?? "")
        _tripID = State(initialValue: existing?.tripID ?? tripID)
    }

    var body: some View {
        Form {
            if legs.isEmpty {
                Section {
                    ModeGrid { mode in
                        let draft = LegDraft(mode: mode)
                        legs = [draft]
                        expandedLeg = draft.id
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
                    pick: { end in picking = EndpointRequest(legID: leg.id, end: end) }
                )
            }

            if let last = legs.last {
                Section {
                    Button("Add Connecting Leg", systemImage: "plus.circle.fill") {
                        let next = last.connecting()
                        legs.append(next)
                        expandedLeg = next.id
                    }
                    .disabled(!last.isComplete)
                }

                Section("Journey") {
                    TextField("Title (optional)", text: $title)
                    TripPicker(selection: $tripID)
                }
            }

            if let existing {
                Section {
                    if existing.legs.count == 1, let leg = existing.legs.first {
                        Button("Ride Again Today", systemImage: "arrow.uturn.forward") {
                            model.rideAgain(leg, tripID: existing.tripID)
                            onDone()
                        }
                    }
                    Button("Delete Journey", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
        }
        .navigationTitle(existing == nil ? "Log Journey" : "Edit Journey")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(existing == nil ? "Save" : "Done", systemImage: "checkmark", action: save)
                    .buttonStyle(.glassProminent)
                    .disabled(legs.isEmpty || !legs.allSatisfy(\.isComplete))
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sheet(item: $picking) { request in
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
            Text("Every leg is removed from your log and your statistics. This can't be undone.")
        }
    }

    @ViewBuilder
    private func endpointPicker(_ request: EndpointRequest) -> some View {
        if let index = legs.firstIndex(where: { $0.id == request.legID }) {
            let mode = legs[index].mode
            PlacePickerSheet(
                title: request.end == .origin ? "From" : "To",
                prompt: "Search \(mode.endpointNoun)s",
                kinds: mode == .flight ? [.airport] : [.city, .landmark, .airport],
                fixedKinds: mode.endpointKinds,
                suggestions: endpointSuggestions(for: mode)
            ) { place in
                guard let index = legs.firstIndex(where: { $0.id == request.legID }) else { return }
                if request.end == .origin {
                    legs[index].origin = place
                } else {
                    legs[index].destination = place
                }
                legs[index].endpointChanged(route: legs[index].routeID.flatMap(model.route(id:)))
            }
        }
    }

    /// Home, then the places the user's recent legs went through — usually where the
    /// next leg starts or ends.
    private func endpointSuggestions(for mode: TravelMode) -> [PlaceReference] {
        var seen: Set<PlaceID> = []
        var places: [PlaceReference] = []
        let recent = model.log.allLegs.reversed().flatMap { [$0.destination, $0.origin] }
            .filter { mode != .flight || $0.kind == .airport }
        let home = mode == .flight ? [] : [model.home].compactMap(\.self)
        for place in home + recent where seen.insert(place.id).inserted {
            places.append(place)
        }
        return Array(places.prefix(8))
    }

    private func remove(_ id: UUID) {
        legs.removeAll { $0.id == id }
        if expandedLeg == id {
            expandedLeg = legs.last?.id
        }
    }

    private func save() {
        let built = legs.compactMap(\.leg)
        guard built.count == legs.count, !built.isEmpty else { return }
        if var journey = existing {
            journey.legs = built
            journey.title = title.trimmedOrNil
            journey.tripID = tripID
            model.updateJourney(journey)
        } else {
            do {
                try model.logJourney(legs: built, tripID: tripID, title: title)
            } catch {
                model.errorMessage = error.localizedDescription
                return
            }
        }
        saved = true
        onDone()
    }
}

/// The eight modes as a grid of tiles (§5.1).
struct ModeGrid: View {
    let pick: (TravelMode) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            ForEach(TravelMode.loggable) { mode in
                Button {
                    pick(mode)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: mode.symbolName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Palette.mode(mode))
                        Text(mode.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(mode.examples)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2, reservesSpace: true)
                        Spacer(minLength: 0)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(
                        Palette.mode(mode).opacity(0.12),
                        in: .rect(cornerRadius: 16, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.displayName)
                .accessibilityHint(mode.examples)
            }
        }
        .padding(.vertical, 4)
    }
}

/// One leg: collapsed to a summary, or expanded into its fields.
private struct LegSection: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: LegDraft
    let number: Int
    let isOnly: Bool
    let isExpanded: Bool
    let expand: () -> Void
    let remove: () -> Void
    let pick: (LegEnd) -> Void

    @State private var showsDetails = false

    var body: some View {
        Section {
            if isExpanded || isOnly {
                fields
            } else {
                Button(action: expand) {
                    LegSummary(draft: draft)
                }
                .buttonStyle(.plain)
            }
        } header: {
            HStack {
                Text(isOnly ? "Leg" : "Leg \(number)")
                Spacer()
                if !isOnly {
                    Menu {
                        Button(
                            isExpanded ? "Collapse" : "Edit",
                            systemImage: "pencil",
                            action: expand
                        )
                        Button(
                            "Remove Leg",
                            systemImage: "trash",
                            role: .destructive,
                            action: remove
                        )
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Leg \(number) options")
                }
            }
        }
    }

    @ViewBuilder
    private var fields: some View {
        if let route = draft.routeName {
            Label {
                VStack(alignment: .leading) {
                    Text(route).font(.headline)
                    Text("Catalogue route. Change either end to log the section you rode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .foregroundStyle(Palette.mode(draft.mode))
            }
        }

        Picker("Mode", selection: $draft.mode) {
            ForEach(TravelMode.loggable) { mode in
                Label(mode.displayName, systemImage: mode.symbolName).tag(mode)
            }
        }

        EndpointButton(label: "From", place: draft.origin, mode: draft.mode) { pick(.origin) }
        EndpointButton(label: "To", place: draft.destination, mode: draft.mode) {
            pick(.destination)
        }

        FlexibleDateField(date: $draft.date)

        if let leg = draft.leg {
            LegDistanceRow(leg: leg)
        }

        DisclosureGroup(isExpanded: $showsDetails) {
            LegDetailFields(draft: $draft)
        } label: {
            Label(
                draft.hasDetails ? "Details" : "Add times, seat and more",
                systemImage: "list.bullet.rectangle"
            )
        }
        .onAppear { showsDetails = draft.hasDetails }
    }
}

private struct EndpointButton: View {
    let label: String
    let place: PlaceReference?
    let mode: TravelMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LabeledContent(label) {
                if let place {
                    HStack(spacing: 6) {
                        if let code = place.code, place.kind == .airport {
                            Text(code).font(.callout.monospaced().weight(.semibold))
                        }
                        Text(place.name).lineLimit(1)
                    }
                    .foregroundStyle(.primary)
                } else {
                    Text("Choose \(mode.endpointNoun)")
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
    }
}

/// One end of a leg.
enum LegEnd: String {
    case origin
    case destination
}
