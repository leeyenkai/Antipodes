import AntipodesCore
import AntipodesGlobe
import SwiftUI

/// A place tapped on the globe, read rather than edited (D-33): where it is, every visit
/// logged there, and the trips they belong to. Editing is one tap further, on a visit —
/// the globe is something to show people, and a form with Delete in view is not.
struct GlobePlaceCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deferredAdd) private var deferredAdd
    let pin: GlobePin
    let close: () -> Void

    var body: some View {
        List {
            Section {
                PlaceHeader(place: pin.place)
            }
            if visits.isEmpty {
                // The last visit here was deleted from its own form, opened from this card.
                ContentUnavailableView("No visits here now", systemImage: "mappin.slash")
            }
            Section {
                ForEach(visits) { visit in
                    NavigationLink(value: LogRoute.visit(visit.id)) {
                        PlaceVisitRow(visit: visit)
                    }
                }
            } header: {
                if !visits.isEmpty {
                    Text(visits.count == 1 ? "Visit" : "\(visits.count) visits")
                }
            } footer: {
                if !visits.isEmpty {
                    Text(visits
                        .count == 1 ? "Open the visit to edit it." : "Open a visit to edit it.")
                }
            }
            if !trips.isEmpty {
                Section(trips.count == 1 ? "Trip" : "Trips") {
                    ForEach(trips) { trip in
                        NavigationLink(value: LogRoute.trip(trip.id)) {
                            LabeledContent(trip.displayName(model: model)) {
                                Text(model.dates(ofTrip: trip.id)?.text ?? "")
                            }
                        }
                    }
                }
            }
            Section {
                Button("Log Another Visit Here", systemImage: "plus") {
                    let request = AddRequest(start: .place(pin.place))
                    if let deferredAdd {
                        deferredAdd(request)
                    } else {
                        close()
                        model.addRequest = request
                    }
                }
            }
        }
        .navigationTitle(pin.place.name)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", role: .cancel, action: close)
            }
        }
    }

    /// Every visit to this place — the one tapped, and any other logged there, which
    /// would otherwise sit under the same pin with no way to reach it. Newest first.
    private var visits: [Visit] {
        model.log.visits
            .filter { $0.id == pin.id || $0.place.id == pin.place.id }
            .sorted { $0.date > $1.date }
    }

    private var trips: [Trip] {
        let ids = Set(visits.compactMap(\.tripID))
        return model.tripsNewestFirst.filter { ids.contains($0.id) }
    }
}

/// A journey tapped on the globe, read rather than edited (D-33): its route, every leg
/// with the tapped one marked, its trip, and buttons to share or edit it.
struct GlobeJourneyCard: View {
    @Environment(AppModel.self) private var model
    let journey: Journey
    /// The leg the tap landed on.
    let legID: UUID
    let close: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(journey.displayTitle)
                        .font(.title3.weight(.semibold))
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section(journey.legs.count == 1 ? "Leg" : "Legs") {
                ForEach(journey.legs) { leg in
                    LegSummaryRow(leg: leg, isTapped: leg.id == legID && journey.legs.count > 1)
                }
            }
            if let tripID = journey.tripID, let trip = model.log.trip(id: tripID) {
                Section("Trip") {
                    NavigationLink(value: LogRoute.trip(trip.id)) {
                        LabeledContent(trip.displayName(model: model)) {
                            Text(model.dates(ofTrip: trip.id)?.text ?? "")
                        }
                    }
                }
            }
            Section {
                NavigationLink(value: LogRoute.journey(journey.id)) {
                    Label("Edit Journey", systemImage: "pencil")
                }
            }
        }
        .navigationTitle(journey.displayTitle)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", role: .cancel, action: close)
            }
        }
        .shareCardButton { .journey(journey) }
    }

    /// "8,588 km · 2 legs · 1 Apr 2024".
    private var summary: String {
        var parts = [
            Format.distance(
                journey.totalDistanceKm,
                model.rules.unitSystem,
                approximate: journey.legs.contains { $0.distanceSource.isApproximate }
            ),
        ]
        if journey.legs.count > 1 {
            parts.append(Format.ordinalCount(journey.legs.count, "leg"))
        }
        parts.append(journey.date.displayText)
        return parts.joined(separator: " · ")
    }
}

/// One leg as a line of a journey card: its mode, ends, distance and service.
private struct LegSummaryRow: View {
    @Environment(AppModel.self) private var model
    let leg: JourneyLeg
    let isTapped: Bool

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(systemName: leg.mode.symbolName, tint: Palette.mode(leg.mode))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(leg.origin.shortName) → \(leg.destination.shortName)")
                    .fontWeight(isTapped ? .semibold : .regular)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if isTapped {
                Image(systemName: "hand.tap")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("The leg you tapped")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        [
            Format.distance(
                leg.distanceKm,
                model.rules.unitSystem,
                approximate: leg.distanceSource.isApproximate
            ),
            leg.serviceNumber,
            leg.date.displayText,
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }
}

/// One visit on a place's card, where the place goes without saying: when, how, and in
/// which trip.
private struct PlaceVisitRow: View {
    @Environment(AppModel.self) private var model
    let visit: Visit

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: visit.visitType.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(visit.date.displayText)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let rating = visit.rating {
                Text(String(repeating: "★", count: rating))
                    .font(.caption2)
                    .foregroundStyle(Palette.pin)
                    .accessibilityLabel("\(rating) stars")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        [
            visit.visitType.displayName,
            visit.tripID.flatMap { model.log.trip(id: $0) }?.displayName(model: model),
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }
}
