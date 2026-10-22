import AntipodesCore
import AntipodesGlobe
import AntipodesStats
import SwiftUI

/// Trips newest first, each with a mini globe and its headline numbers, and everything
/// not yet filed under a trip (§9).
struct TripsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var searchText = ""
    @State private var isCreatingTrip = false
    @State private var tripToDelete: Trip?

    var body: some View {
        GlobeBesideStack(tab: .trips) {
            List {
                if model.log.isEmpty {
                    EmptyStateView(
                        title: "Nothing logged yet",
                        message: """
                        Log a place or a journey, then group them into trips — or bring in \
                        what you've already got.
                        """,
                        systemImage: "suitcase",
                        actionTitle: "Log a Place or Journey",
                        action: { model.addRequest = AddRequest() },
                        otherActions: EmptyStateAction.imports(model)
                    )
                    .listRowBackground(Color.clear)
                }

                ForEach(groupedTrips, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.trips) { trip in
                            NavigationLink(value: LogRoute.trip(trip.id)) {
                                TripRow(trip: trip)
                            }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    tripToDelete = trip
                                }
                            }
                            .contextMenu {
                                Button("Delete Trip…", systemImage: "trash", role: .destructive) {
                                    tripToDelete = trip
                                }
                            }
                        }
                    }
                }

                UnfiledSection(searchText: searchText)
            }
            .overlay {
                if hasNoMatches {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .navigationTitle("Trips")
            .addToolbarButton()
            .searchable(text: $searchText, prompt: "Trips and places")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("New Trip…", systemImage: "suitcase") { isCreatingTrip = true }
                        Button("Log a Place", systemImage: "mappin.and.ellipse") {
                            model.addRequest = AddRequest()
                        }
                        Button("Log a Journey", systemImage: "airplane") {
                            model.addRequest = AddRequest(start: .journey(nil))
                        }
                        Menu("Import", systemImage: "square.and.arrow.down") {
                            Button("Flights or Rail Logs…", systemImage: "airplane.arrival") {
                                model.importRequest = .journeys
                            }
                            Button(
                                "Visits from Photos…",
                                systemImage: "photo.on.rectangle.angled"
                            ) {
                                model.importRequest = .photos
                            }
                        }
                        // With a sidebar, All Records is a destination of its own.
                        if !DeviceLayout.hasSidebar(sizeClass) {
                            Divider()
                            NavigationLink(value: LogRoute.allVisits) {
                                Label("All Records", systemImage: "tablecells")
                            }
                        }
                    } label: {
                        // Beside the Log button a sidebar layout has, a second "+" would look
                        // like the same action twice.
                        Label(
                            "Add",
                            systemImage: DeviceLayout
                                .hasSidebar(sizeClass) ? "ellipsis.circle" : "plus"
                        )
                    }
                }
            }
            .logDestinations()
            .newTripAlert(isPresented: $isCreatingTrip)
            .deleteTripDialog(trip: $tripToDelete)
        }
    }

    /// A search that found no trip and nothing unfiled says so, rather than showing a
    /// blank list.
    private var hasNoMatches: Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty, filteredTrips.isEmpty else { return false }
        let unfiledVisit = model.log.visits.contains {
            $0.tripID == nil && $0.place.name.lowercased().contains(query)
        }
        let unfiledJourney = model.log.journeys.contains {
            $0.tripID == nil && $0.displayTitle.lowercased().contains(query)
        }
        return !unfiledVisit && !unfiledJourney
    }

    private var filteredTrips: [Trip] {
        let trips = model.tripsNewestFirst
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return trips }
        return trips.filter { trip in
            trip.displayName(model: model).lowercased().contains(query)
                || model.visits(inTrip: trip.id)
                .contains { $0.place.name.lowercased().contains(query) }
        }
    }

    /// Trips by the year they started, newest first, with undated trips last.
    private var groupedTrips: [(title: String, trips: [Trip])] {
        var byYear: [Int: [Trip]] = [:]
        var undated: [Trip] = []
        for trip in filteredTrips {
            if let year = model.dates(ofTrip: trip.id)?.start.year {
                byYear[year, default: []].append(trip)
            } else {
                undated.append(trip)
            }
        }
        var groups = byYear.keys.sorted(by: >).map { (title: String($0), trips: byYear[$0] ?? []) }
        if !undated.isEmpty {
            groups.append((title: "Undated", trips: undated))
        }
        return groups
    }
}

private struct TripRow: View {
    @Environment(AppModel.self) private var model
    let trip: Trip

    var body: some View {
        HStack(spacing: 14) {
            MiniGlobe.trip(trip.id, model: model)
                .frame(width: 58, height: 58)
                .clipShape(.rect(cornerRadius: Radius.tile, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.displayName(model: model))
                    .font(.headline)
                    .lineLimit(1)
                if let dates = model.dates(ofTrip: trip.id), trip.name != nil {
                    Text(dates.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let visits = model.visits(inTrip: trip.id)
        let journeys = model.journeys(inTrip: trip.id)
        // The same rule as the trip's own header and every other count: a layover does
        // not add a country unless the user counts layovers.
        let counted = visits.filter { model.rules.countsTowardsCoverage($0.visitType) }
        let countries = Set(counted.compactMap(\.place.countryCode)).count
        var parts: [String] = []
        if countries > 0 {
            parts.append(Format.ordinalCount(countries, "country", "countries"))
        }
        parts.append(Format.ordinalCount(visits.count, "place"))
        // Commute legs follow the rule too, so this matches the trip's own header.
        let legs = journeys.flatMap(\.legs).filter { model.rules.countsInStats($0.purpose) }
        if !legs.isEmpty {
            let kilometres = legs.reduce(0) { $0 + $1.distanceKm }
            parts.append(Format.distance(kilometres, model.rules.unitSystem))
        }
        let flags = Set(counted.compactMap(\.place.countryCode)).sorted().prefix(5).map(Format.flag)
            .joined()
        return ([flags] + parts).filter { !$0.isEmpty }.joined(separator: "  ")
    }
}

/// Visits and journeys not filed under any trip (R-MODEL-3).
private struct UnfiledSection: View {
    @Environment(AppModel.self) private var model
    let searchText: String

    var body: some View {
        let visits = model.log.visits
            .filter { $0.tripID == nil && matches($0.place.name) }
            .sorted { $0.date > $1.date }
        let journeys = model.log.journeys
            .filter { $0.tripID == nil && matches($0.displayTitle) }
            .sorted { $0.date > $1.date }
        if !visits.isEmpty || !journeys.isEmpty {
            Section {
                ForEach(journeys) { journey in
                    NavigationLink(value: LogRoute.journey(journey.id)) {
                        JourneyRow(journey: journey)
                    }
                    .recordActions(
                        moveTo: MoveToTripMenu(journeyIDs: [journey.id]),
                        delete: { model.deleteJourneys([journey.id]) }
                    )
                }
                ForEach(visits) { visit in
                    NavigationLink(value: LogRoute.visit(visit.id)) {
                        VisitRow(visit: visit)
                    }
                    .recordActions(
                        moveTo: MoveToTripMenu(visitIDs: [visit.id]),
                        delete: { model.deleteVisits([visit.id]) }
                    )
                }
            } header: {
                Text("Not in a trip")
            } footer: {
                Text(Self.hint)
            }
        }
    }

    private func matches(_ text: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty || text.lowercased().contains(query)
    }

    /// How to file or delete one of these, in the words of the device in hand.
    private static var hint: String {
        #if os(macOS)
            "Control-click a place or journey to file it under a trip or delete it."
        #else
            "Swipe to delete, or touch and hold to file under a trip."
        #endif
    }
}

extension View {
    /// The actions on a record in a list, the same everywhere: Delete by swipe and in the
    /// context menu — which is how a pointer reaches it on the Mac — and, where given,
    /// Move to Trip beside it. Deleting asks nothing first; the undo toast offers it back.
    func recordActions(
        moveTo: MoveToTripMenu? = nil,
        delete: @escaping () -> Void
    ) -> some View {
        swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        }
        .contextMenu {
            if let moveTo {
                moveTo
            }
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        }
    }
}

/// Files records under a trip from a context menu.
struct MoveToTripMenu: View {
    @Environment(AppModel.self) private var model
    var visitIDs: [UUID] = []
    var journeyIDs: [UUID] = []

    var body: some View {
        Menu("Move to Trip", systemImage: "suitcase") {
            Button("No Trip") { move(to: nil) }
            Divider()
            ForEach(model.tripsNewestFirst) { trip in
                Button(trip.displayName(model: model)) { move(to: trip.id) }
            }
        }
    }

    private func move(to tripID: UUID?) {
        if !visitIDs.isEmpty {
            model.moveVisits(visitIDs, toTrip: tripID)
        }
        if !journeyIDs.isEmpty {
            model.moveJourneys(journeyIDs, toTrip: tripID)
        }
    }
}

extension View {
    /// Asks whether deleting a trip should keep what was in it — the default — or
    /// remove that too.
    func deleteTripDialog(trip: Binding<Trip?>, onDeleted: @escaping () -> Void = {}) -> some View {
        modifier(DeleteTripDialog(trip: trip, onDeleted: onDeleted))
    }
}

private struct DeleteTripDialog: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var trip: Trip?
    let onDeleted: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete \(trip?.displayName(model: model) ?? "trip")?",
            isPresented: Binding(get: { trip != nil }, set: {
                if !$0 {
                    trip = nil
                }
            }),
            titleVisibility: .visible,
            presenting: trip
        ) { trip in
            Button("Delete Trip, Keep What's in It") {
                model.deleteTrip(trip.id, deletingContents: false)
                onDeleted()
            }
            Button("Delete Trip and Everything in It", role: .destructive) {
                model.deleteTrip(trip.id, deletingContents: true)
                onDeleted()
            }
        } message: { _ in
            Text("""
            Keeping its places and journeys leaves them in your log, not in any trip. \
            You can undo either straight afterwards.
            """)
        }
    }
}

extension View {
    /// "New trip": names a trip, creates it, and opens it.
    func newTripAlert(isPresented: Binding<Bool>) -> some View {
        modifier(NewTripAlert(isPresented: isPresented))
    }
}

/// Inside the Trips stack, so it can open what it makes there.
private struct NewTripAlert: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(GlobeBesideContext.self) private var beside: GlobeBesideContext?
    @Binding var isPresented: Bool
    @State private var name = ""

    func body(content: Content) -> some View {
        content.alert("New trip", isPresented: $isPresented) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) { name = "" }
            Button("Create") {
                do {
                    // Opened straight away: an empty trip at the foot of the list, under
                    // "Undated", is easy to lose.
                    let trip = try model.createTrip(name: name)
                    beside?.path.append(LogRoute.trip(trip.id))
                } catch {
                    model.errorMessage = AppModel.tripNotCreated(error)
                }
                name = ""
            }
        } message: {
            Text("Then add what you've logged, or log something new in it.")
        }
    }
}
