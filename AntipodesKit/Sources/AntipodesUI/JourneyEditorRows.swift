import AntipodesCore
import SwiftUI

/// The leg's distance and where it comes from, so an approximate figure says so
/// before it is saved (R-PATH-3).
struct LegDistanceRow: View {
    @Environment(AppModel.self) private var model
    let leg: JourneyLeg

    var body: some View {
        let distance = leg.distance
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Distance") {
                Text(Format.distance(
                    distance.kilometres,
                    model.rules.unitSystem,
                    approximate: distance.source.isApproximate
                ))
                .monospacedDigit()
            }
            Text(sourceText(distance.source))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let minutes = leg.durationMinutes {
                LabeledContent("Duration", value: Format.duration(minutes: minutes))
            }
        }
    }

    private func mapName(_ kind: TrackKind?) -> String {
        kind?.isFromRoutePack == true ? "OpenStreetMap's" : "Natural Earth's"
    }

    private func sourceText(_ source: DistanceSource) -> String {
        switch source {
        case .userOverride: "Your own figure."
        case .recordedTrack: "The track your device recorded."
        case .storedPath where leg.transitLineID != nil: "Along the line, stop to stop."
        case .storedPath where leg.isMeasuredAlongTrack:
            "Along \(leg.trackKind?.routeNoun ?? "the way"), on \(mapName(leg.trackKind)) map."
        case .storedPath: "The catalogue route's length\(leg.routeName.map { " (\($0))" } ?? "")."
        case .greatCircleExact: "Great-circle distance between the airports."
        case .greatCircleApproximate: leg.mode.pathSourceDescription
        case .unavailable: "One of the ends has no location, so there is no distance."
        }
    }
}

/// A collapsed leg.
struct LegSummary: View {
    @Environment(AppModel.self) private var model
    let draft: LegDraft

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(systemName: draft.mode.symbolName, tint: Palette.mode(draft.mode))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(draft.origin?.shortName ?? "?") → \(draft.destination?.shortName ?? "?")")
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }

    private var detail: String {
        var parts = [draft.date.displayText]
        if let leg = draft.leg {
            parts.append(Format.distance(
                leg.distanceKm,
                model.rules.unitSystem,
                approximate: leg.distanceSource.isApproximate
            ))
        }
        return parts.joined(separator: " · ")
    }
}

/// The change between two legs: how long it was, and whether it was missed.
struct ConnectionRow: View {
    let previous: LegDraft
    @Binding var next: LegDraft

    var body: some View {
        Section {
            HStack {
                Image(
                    systemName: next.missedConnection
                        ? "exclamationmark.arrow.triangle.2.circlepath"
                        : "arrow.triangle.swap"
                )
                .foregroundStyle(next.missedConnection ? Palette.warning : .secondary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Missed", isOn: $next.missedConnection)
                    .labelsHidden()
                    .accessibilityLabel("Missed connection")
            }
        } footer: {
            if next.missedConnection {
                Text("Marked as a missed connection.")
            }
        }
    }

    private var text: String {
        guard let arriving = previous.leg, let departing = next.leg else {
            return "Connection"
        }
        let journey = Journey(legs: [arriving, departing])
        guard let connection = journey.connections.first else { return "Connection" }
        var parts: [String] = []
        if connection.changesPlace {
            parts
                .append(
                    "Change from \(arriving.destination.shortName) to \(departing.origin.shortName)"
                )
        } else {
            parts.append("Change at \(arriving.destination.shortName)")
        }
        if let minutes = connection.minutes {
            parts.append(Format.duration(minutes: minutes))
        }
        return parts.joined(separator: " · ")
    }
}

/// The last few rides, each logged again for today with one tap (R-JLOG-6): the
/// commuter's train, the ferry taken every summer.
struct RecentRides: View {
    @Environment(AppModel.self) private var model
    let tripID: UUID?
    let onDone: () -> Void

    var body: some View {
        let rides = recent
        if !rides.isEmpty {
            Section {
                ForEach(rides, id: \.leg.id) { ride in
                    Button {
                        model.rideAgain(ride.leg, tripID: tripID ?? ride.tripID)
                        onDone()
                    } label: {
                        HStack(spacing: 12) {
                            SymbolTile(
                                systemName: ride.leg.mode.symbolName,
                                tint: Palette.mode(ride.leg.mode)
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ride.leg.routeTitle)
                                    .foregroundStyle(.primary)
                                Text(ride.leg.date.displayText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.uturn.forward")
                                .foregroundStyle(.tint)
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(.rect)
                    .accessibilityLabel(
                        "Ride again today: \(ride.leg.origin.name) to \(ride.leg.destination.name)"
                    )
                }
            } header: {
                Text("Ride again today")
            }
        }
    }

    /// The most recent rides by date, each route and mode once.
    private var recent: [(leg: JourneyLeg, tripID: UUID?)] {
        var seen: Set<String> = []
        return model.log.journeys
            .flatMap { journey in journey.legs.map { (leg: $0, tripID: journey.tripID) } }
            .sorted { $0.leg.date > $1.leg.date }
            .filter { ride in
                seen.insert(
                    "\(ride.leg.mode.rawValue) \(ride.leg.origin.id) \(ride.leg.destination.id)"
                ).inserted
            }
            .prefix(4)
            .map(\.self)
    }
}

extension JourneyLeg {
    /// "Oslo → Bergen".
    var routeTitle: String {
        "\(origin.shortName) → \(destination.shortName)"
    }
}

/// The eight modes as a grid of tiles (§5.1).
struct ModeGrid: View {
    let pick: (TravelMode) -> Void
    @ScaledMetric(relativeTo: .title2) private var iconHeight: CGFloat = 30

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            ForEach(TravelMode.loggable) { mode in
                Button {
                    pick(mode)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        // Symbols differ in height; a fixed band keeps every tile's title
                        // on the same line as its neighbour's.
                        Image(systemName: mode.symbolName)
                            .font(.title2.weight(.light))
                            .foregroundStyle(Palette.mode(mode))
                            .frame(height: iconHeight, alignment: .bottomLeading)
                        Text(mode.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(mode.examples)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3, reservesSpace: true)
                        Spacer(minLength: 0)
                    }
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(
                        .fill.tertiary,
                        in: .rect(cornerRadius: Radius.tile, style: .continuous)
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

/// One end of a leg in its form: the place chosen, or a prompt to choose one.
struct EndpointButton: View {
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

/// "Also log a stay in Tokyo": a journey's arrival logged as a visit, so the country it
/// reached counts — coverage comes from visits (R-CALC-1, D-32).
struct ArrivalSection: View {
    let arrivals: [Arrival]
    @Binding var isOn: Bool

    private var names: String {
        arrivals.map(\.place.name).formatted(.list(type: .and))
    }

    var body: some View {
        Section {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Also log a stay in \(names)")
                    Text("So the places you arrived at count towards your countries and cities.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
