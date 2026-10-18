import AntipodesCore
import SwiftUI

/// Trips newest first, with the loose visits that have not been filed yet (§9).
struct TripsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                if model.log.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing logged yet", systemImage: "suitcase")
                    } description: {
                        Text("Tap the plus button to log a place or a flight.")
                    }
                }

                ForEach(model.log.trips, id: \.id) { trip in
                    NavigationLink(value: trip.id) {
                        TripRow(trip: trip)
                    }
                }

                if !unfiledVisits.isEmpty {
                    Section("Not in a trip") {
                        ForEach(unfiledVisits, id: \.id) { visit in
                            VisitRow(visit: visit)
                        }
                    }
                }
            }
            .navigationTitle("Trips")
            .navigationDestination(for: UUID.self) { tripID in
                TripDetailView(tripID: tripID)
            }
        }
    }

    private var unfiledVisits: [Visit] {
        model.log.visits.filter { $0.tripID == nil }.sorted { $0.date > $1.date }
    }
}

private struct TripRow: View {
    @Environment(AppModel.self) private var model
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trip.name ?? "Untitled trip")
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        let visits = model.log.visits(inTrip: trip.id).count
        let journeys = model.log.journeys(inTrip: trip.id)
        let kilometres = journeys.reduce(0) { $0 + $1.totalDistanceKm }
        let distance = model.rules.unitSystem.distance(fromKilometres: kilometres)
        let unit = model.rules.unitSystem.distanceUnitAbbreviation

        var parts = ["\(visits) place\(visits == 1 ? "" : "s")"]
        if !journeys.isEmpty {
            parts.append("\(journeys.count) journey\(journeys.count == 1 ? "" : "s")")
            parts.append("\(Int(distance.rounded())) \(unit)")
        }
        return parts.joined(separator: " · ")
    }
}

private struct TripDetailView: View {
    @Environment(AppModel.self) private var model
    let tripID: UUID

    private var trip: Trip? {
        model.log.trips.first { $0.id == tripID }
    }

    var body: some View {
        List {
            Section("Places") {
                let visits = model.log.visits(inTrip: tripID).sorted { $0.date < $1.date }
                if visits.isEmpty {
                    Text("No places logged in this trip.").foregroundStyle(.secondary)
                }
                ForEach(visits, id: \.id) { VisitRow(visit: $0) }
            }

            Section("Journeys") {
                let journeys = model.log.journeys(inTrip: tripID).sorted { $0.date < $1.date }
                if journeys.isEmpty {
                    Text("No journeys logged in this trip.").foregroundStyle(.secondary)
                }
                ForEach(journeys, id: \.id) { JourneyRow(journey: $0) }
            }
        }
        .navigationTitle(trip?.name ?? "Trip")
    }
}

struct VisitRow: View {
    let visit: Visit

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: visit.place.kind.symbolName)
                .frame(width: 22)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(visit.place.name)
                Text("\(visit.visitType.displayName) · \(visit.date.displayText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct JourneyRow: View {
    @Environment(AppModel.self) private var model
    let journey: Journey

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: journey.legs.first?.mode.symbolName ?? "arrow.right")
                .frame(width: 22)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var title: String {
        if let title = journey.title {
            return title
        }
        let from = journey.origin?.code ?? journey.origin?.name ?? "?"
        let to = journey.destination?.code ?? journey.destination?.name ?? "?"
        return "\(from) → \(to)"
    }

    private var detail: String {
        let distance = model.rules.unitSystem.distance(fromKilometres: journey.totalDistanceKm)
        let unit = model.rules.unitSystem.distanceUnitAbbreviation
        return "\(Int(distance.rounded())) \(unit) · \(journey.date.displayText)"
    }
}

private extension PlaceReference {
    /// Airport codes make a far better journey title than full airport names.
    var code: String? {
        guard kind == .airport else { return nil }
        let words = name.split(separator: " ")
        return words.count == 1 ? String(words[0]) : nil
    }
}
