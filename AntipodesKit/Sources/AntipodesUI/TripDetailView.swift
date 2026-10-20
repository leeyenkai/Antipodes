import AntipodesCore
import AntipodesStats
import SwiftUI

/// One trip: its map, its places and journeys, and its own statistics (§9).
struct TripDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID

    @State private var isEditing = false
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
        let visits = model.log.visits(inTrip: tripID).sorted { $0.date < $1.date }
        let journeys = model.log.journeys(inTrip: tripID).sorted { $0.date < $1.date }

        return List {
            Section {
                TripHeader(trip: trip, stats: tripStats)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Button("Add to This Trip", systemImage: "plus") {
                    model.addRequest = AddRequest(tripID: tripID)
                }
                if let notes = trip.notes, !notes.isEmpty {
                    Text(notes)
                        .foregroundStyle(.secondary)
                }
            }

            if !journeys.isEmpty {
                Section("Journeys") {
                    ForEach(journeys) { journey in
                        NavigationLink(value: LogRoute.journey(journey.id)) {
                            JourneyRow(journey: journey)
                        }
                        .contextMenu { MoveToTripMenu(journeyIDs: [journey.id]) }
                    }
                    .onDelete { offsets in
                        model.deleteJourneys(offsets.map { journeys[$0].id })
                    }
                }
            }

            Section(visits.isEmpty ? "" : "Places") {
                if visits.isEmpty {
                    Text("No places in this trip yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(visits) { visit in
                    NavigationLink(value: LogRoute.visit(visit.id)) {
                        VisitRow(visit: visit)
                    }
                    .contextMenu { MoveToTripMenu(visitIDs: [visit.id]) }
                }
                .onDelete { offsets in
                    model.deleteVisits(offsets.map { visits[$0].id })
                }
            }

            TripStatsSection(stats: tripStats)
        }
        .navigationTitle(trip.displayName(model: model))
        .toolbarTitleDisplayMode(.inline)
        .toolbar { toolbar(trip) }
        .globeFocus(.trip(tripID))
        .sheet(isPresented: $isEditing) {
            TripEditor(trip: trip)
        }
        .deleteTripDialog(trip: $tripToDelete) { dismiss() }
        .task(id: model.statisticsRevision) {
            stats = await model.computeStatistics(forTrip: tripID)
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ trip: Trip) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ShareLink(
                item: ShareCardImage(card: .trip(tripID), model: model),
                preview: SharePreview(
                    trip.displayName(model: model),
                    image: Image(systemName: "suitcase")
                )
            )
        }
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
                metric("\(stats.coverage.countriesVisited)", "Countries")
                Divider().frame(height: 32)
                metric("\(stats.coverage.citiesVisited)", "Cities")
                Divider().frame(height: 32)
                metric(Format.distance(stats.distance.totalKm, model.rules.unitSystem), "Travelled")
            }
            .padding(.vertical, 12)
            .background(.background.secondary)
        }
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.statValue(20))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var updated = trip
                        updated.name = name.trimmedOrNil
                        updated.notes = notes.trimmedOrNil
                        model.updateTrip(updated)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
