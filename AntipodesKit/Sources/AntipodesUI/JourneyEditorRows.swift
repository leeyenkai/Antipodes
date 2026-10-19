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

    private func sourceText(_ source: DistanceSource) -> String {
        switch source {
        case .userOverride: "Your own figure."
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
