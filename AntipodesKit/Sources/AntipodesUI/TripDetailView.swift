import AntipodesCore
import AntipodesStats
import SwiftUI

/// One trip: its map, its places and journeys, and its own statistics (§9).
struct TripDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID

    @State private var isEditing = false
    @State private var isAddingExisting = false
    @State private var tripToDelete: Trip?
    /// The trip's own statistics, worked out off the main thread whenever the log's
    /// change, rather than twice on every redraw.
    @State private var stats: TravelStatistics?

    var body: some View {
        if let trip = model.log.trip(id: tripID) {
            content(trip)
        } else {
            ContentUnavailableView("Trip deleted", systemImage: "trash")
        }
    }

    private func content(_ trip: Trip) -> some View {
        let tripStats = stats ?? model.emptyStatistics
        let visits = model.visits(inTrip: tripID).sorted { $0.date < $1.date }
        let journeys = model.journeys(inTrip: tripID).sorted { $0.date < $1.date }

        return List {
            Section {
                TripHeader(trip: trip, stats: tripStats)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Button("Log Something New", systemImage: "plus") {
                    // Logged after the fact, more often than not: start on the trip's
                    // last day rather than today.
                    model.addRequest = AddRequest(
                        tripID: tripID,
                        date: model.dates(ofTrip: tripID).map { .day($0.end) }
                    )
                }
                Button(
                    "Add Places and Journeys Already Logged…",
                    systemImage: "tray.and.arrow.down"
                ) {
                    isAddingExisting = true
                }
                if let notes = trip.notes, !notes.isEmpty {
                    Text(notes)
                        .foregroundStyle(.secondary)
                }
            }

            TripPhotosSection(trip: trip, visits: visits)

            TripRecordsSections(visits: visits, journeys: journeys)

            TripStatsSection(stats: tripStats)
        }
        .navigationTitle(trip.displayName(model: model))
        .toolbarTitleDisplayMode(.inline)
        .toolbar { toolbar(trip) }
        .shareCardButton { .trip(tripID) }
        .globeFocus(.trip(tripID))
        .sheet(isPresented: $isEditing) {
            TripEditor(trip: trip)
        }
        .sheet(isPresented: $isAddingExisting) {
            AddExistingToTripSheet(tripID: tripID)
        }
        .deleteTripDialog(trip: $tripToDelete) { dismiss() }
        .task(id: model.statisticsRevision) {
            stats = await model.computeStatistics(forTrip: tripID)
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ trip: Trip) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Edit Name and Notes", systemImage: "pencil") { isEditing = true }
                Button("Delete Trip", systemImage: "trash", role: .destructive) {
                    tripToDelete = trip
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
    }
}

private struct TripHeader: View {
    @Environment(AppModel.self) private var model
    let trip: Trip
    let stats: TravelStatistics

    var body: some View {
        VStack(spacing: 0) {
            MiniGlobe.trip(trip.id, model: model)
                .frame(height: 220)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trip.displayName(model: model))
                            .font(.title2.weight(.bold))
                        if let dates = model.dates(ofTrip: trip.id) {
                            Text(dates.textWithLength)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 6)
                }
            HStack(spacing: 0) {
                metric(
                    "\(stats.coverage.countriesVisited)",
                    stats.coverage.countriesVisited == 1 ? "Country" : "Countries"
                )
                Divider().frame(height: 32)
                metric(
                    "\(stats.coverage.citiesVisited)",
                    stats.coverage.citiesVisited == 1 ? "City" : "Cities"
                )
                Divider().frame(height: 32)
                metric(Format.distance(stats.distance.totalKm, model.rules.unitSystem), "Travelled")
            }
            .padding(.vertical, 12)
            .background(.background.secondary)
        }
        .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .figure(.inline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The trip's journeys and places, each with the record actions every list has.
private struct TripRecordsSections: View {
    @Environment(AppModel.self) private var model
    let visits: [Visit]
    let journeys: [Journey]

    var body: some View {
        if !journeys.isEmpty {
            Section("Journeys") {
                ForEach(journeys) { journey in
                    NavigationLink(value: LogRoute.journey(journey.id)) {
                        JourneyRow(journey: journey)
                    }
                    .recordActions(
                        moveTo: MoveToTripMenu(journeyIDs: [journey.id]),
                        delete: { model.deleteJourneys([journey.id]) }
                    )
                }
            }
        }
        if visits.isEmpty, journeys.isEmpty {
            Section {
                Text("""
                Nothing in this trip yet. Log something new in it, or add what you've \
                already logged.
                """)
                .foregroundStyle(.secondary)
            }
        }
        if !visits.isEmpty {
            Section("Places") {
                ForEach(visits) { visit in
                    NavigationLink(value: LogRoute.visit(visit.id)) {
                        VisitRow(visit: visit)
                    }
                    .recordActions(
                        moveTo: MoveToTripMenu(visitIDs: [visit.id]),
                        delete: { model.deleteVisits([visit.id]) }
                    )
                }
            }
        }
    }
}

/// The trip's own numbers, from the same engine and rules as the whole log.
private struct TripStatsSection: View {
    @Environment(AppModel.self) private var model
    let stats: TravelStatistics

    var body: some View {
        Section("This trip") {
            if stats.flights.flightCount > 0 {
                DetailRow(
                    title: "Flights",
                    value: "\(stats.flights.flightCount)",
                    systemImage: "airplane"
                )
            }
            if let longest = stats.distance.longestLeg {
                DetailRow(
                    title: "Longest leg",
                    value: "\(longest.origin.shortName) → \(longest.destination.shortName)",
                    systemImage: "arrow.left.and.right"
                )
            }
            if stats.journeys.totalMinutes > 0 {
                DetailRow(
                    title: "Time travelling",
                    value: Format.duration(minutes: stats.journeys.totalMinutes),
                    systemImage: "clock"
                )
            }
            if stats.carbon.totalKg > 0 {
                DetailRow(
                    title: "Carbon (estimate)",
                    value: Format.carbon(kilograms: stats.carbon.totalKg),
                    systemImage: "leaf"
                )
                Text(stats.carbon.shortCredit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let top = stats.themes.topThemes.first {
                DetailRow(title: "Top theme", value: top.label, systemImage: "sparkles")
            }
            if stats.coverage.landmarksVisited > 0 {
                DetailRow(
                    title: "Landmarks",
                    value: "\(stats.coverage.landmarksVisited)",
                    systemImage: "building.columns"
                )
            }
            if let caveat = stats.coverage.input.caveat {
                CaveatLabel(text: caveat)
            }
        }
    }
}

/// Renames a trip and edits its notes.
struct TripEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    @State private var name: String
    @State private var notes: String

    init(trip: Trip) {
        self.trip = trip
        _name = State(initialValue: trip.name ?? "")
        _notes = State(initialValue: trip.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3 ... 10)
            }
            .navigationTitle("Edit Trip")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                }
            }
            // The guard reads its placement from outside itself.
            .guardingUnsavedEdits(hasChanges) { dismiss() }
            .environment(\.editorPlacement, .root)
        }
        .presentationDetents([.medium])
    }

    private var hasChanges: Bool {
        name.trimmedOrNil != trip.name?.trimmedOrNil || notes.trimmedOrNil != trip.notes?
            .trimmedOrNil
    }

    /// A failed save keeps the sheet open with the edits in it; the app-wide alert says
    /// what went wrong.
    private func save() {
        guard hasChanges else {
            dismiss()
            return
        }
        var updated = trip
        updated.name = name.trimmedOrNil
        updated.notes = notes.trimmedOrNil
        if model.updateTrip(updated) {
            dismiss()
        }
    }
}
