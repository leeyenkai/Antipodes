import AntipodesCore
import AntipodesStats
import SwiftUI

/// The legs behind a figure, newest first — or latest-arriving first for punctuality —
/// under the same rules as the figure.
struct LegListView: View {
    @Environment(AppModel.self) private var model
    let filter: LegFilter
    var showsCarbon = false

    var body: some View {
        // The same rule as the numbers this list explains: commutes are left out
        // unless Settings counts them.
        let matching = model.shownLog.journeys.flatMap { journey in
            journey.legs.filter { filter.includes($0, in: journey) }
                .map { (journey: journey, leg: $0) }
        }
        let rows = matching
            .filter { model.shownRules.countsInStats($0.leg.purpose) }
            .sorted { first, second in
                if filter == .timed {
                    return (first.leg.times.arrivalDelayMinutes ?? 0)
                        > (second.leg.times.arrivalDelayMinutes ?? 0)
                }
                return first.leg.date > second.leg.date
            }
        let commutesLeftOut = matching.count - rows.count
        List {
            Section {
                ForEach(rows, id: \.leg.id) { row in
                    NavigationLink(value: LogRoute.journey(row.journey.id)) {
                        LegListRow(leg: row.leg, figure: figure(for: row.leg))
                    }
                    // Not a full swipe: logging a whole journey should take a deliberate tap.
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button("Ride Again", systemImage: "arrow.uturn.forward") {
                            model.rideAgain(row.leg, tripID: row.journey.tripID)
                        }
                        .tint(Palette.visited)
                    }
                }
            } footer: {
                if showsCarbon {
                    Text(model.shownStatistics.carbon.shortCredit + ", per passenger.")
                }
                if commutesLeftOut > 0 {
                    Text("""
                    \(Format.ordinalCount(commutesLeftOut, "commute leg")) left out, as in the \
                    totals. Settings › What counts can include commutes.
                    """)
                }
            }
            if rows.isEmpty {
                ContentUnavailableView(
                    "No legs",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
            }
        }
        .navigationTitle(showsCarbon ? "Carbon by leg" : filter.title)
    }

    /// What the row shows on the right: carbon, a delay, or the distance and time.
    private func figure(for leg: JourneyLeg) -> LegListRow.Figure {
        if showsCarbon {
            let saved = model.shownStatistics.carbon.savedByLeg[leg.id]
                .flatMap { $0 > 0 ? $0 : nil }
            return LegListRow.Figure(
                main: model.shownStatistics.carbon.kgByLeg[leg.id]
                    .map { Format.carbon(kilograms: $0) } ?? "—",
                secondary: saved.map { "saved \(Format.carbon(kilograms: $0))" },
                highlightsSecondary: true
            )
        }
        if filter == .timed, let delay = leg.times.arrivalDelayMinutes {
            return LegListRow.Figure(main: Format.delay(minutes: Double(delay)), secondary: nil)
        }
        return LegListRow.Figure(
            main: Format.distance(
                leg.distanceKm,
                model.rules.unitSystem,
                approximate: leg.distanceSource.isApproximate
            ),
            secondary: leg.durationMinutes.map { Format.duration(minutes: $0) }
        )
    }
}

/// One leg in a list: its mode, its two ends and its date, and a figure on the right.
struct LegListRow: View {
    struct Figure {
        let main: String
        let secondary: String?
        var highlightsSecondary = false
    }

    let leg: JourneyLeg
    let figure: Figure

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(systemName: leg.mode.symbolName, tint: Palette.mode(leg.mode))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(leg.origin.shortName) → \(leg.destination.shortName)")
                Text(leg.date.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(figure.main)
                if let secondary = figure.secondary {
                    Text(secondary)
                        .font(.caption2)
                        .foregroundStyle(figure.highlightsSecondary
                            ? AnyShapeStyle(Palette.visited) : AnyShapeStyle(.secondary))
                }
            }
            .font(.subheadline.monospacedDigit())
        }
    }
}
