import AntipodesCore
import AntipodesStats
import SwiftUI

// MARK: - Rail, road and sea

/// The rail, and the road and sea, groups of the journey stats (§5.7).
struct JourneyDetailSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let rail = model.shownStatistics.rail
        let roadAndSea = model.shownStatistics.roadAndSea
        if rail.legCount > 0 || roadAndSea.hasAnything {
            StatsSection(title: "Rail, road and sea", symbol: "tram") {
                if rail.legCount > 0 {
                    railCard(rail)
                }
                if roadAndSea.hasAnything {
                    roadAndSeaCard(roadAndSea)
                }
            }
        }
        PunctualitySection()
    }

    private func railCard(_ rail: RailStatistics) -> some View {
        StatCardList {
            StatRow("Rail legs", "\(rail.legCount)", symbol: "tram", route: .legs(.rail))
            StatRow(
                "Rail distance",
                Format.distance(rail.kilometres, model.rules.unitSystem),
                symbol: "ruler",
                detail: rail.kilometreInput.caveat(counting: "rail legs"),
                route: .legs(.rail)
            )
            StatRow(
                "Stations",
                "\(rail.stations.count)",
                symbol: "signpost.right",
                route: .legs(.rail)
            )
            namedRow("Operators", rail.operators, symbol: "building", route: .legs(.rail))
            namedRow("Classes", rail.classes, symbol: "chair", route: .legs(.rail))
            namedRow(
                "Train types",
                rail.trainTypes,
                symbol: "train.side.front.car",
                route: .legs(.rail)
            )
            namedRow("Named services", rail.namedServices, symbol: "star", route: .legs(.rail))
            StatRow(
                "Night trains",
                "\(rail.overnightLegs)",
                symbol: "bed.double",
                route: .legFilter(.overnight)
            )
            StatRow(
                "Countries by rail",
                "\(rail.countries.count)",
                symbol: "flag",
                detail: "\(Format.ordinalCount(rail.bordersCrossed, "border")) crossed",
                route: .legs(.rail)
            )
            if let highest = rail.highestPointM {
                StatRow(
                    "Highest by rail",
                    Format.elevation(highest, model.rules.unitSystem),
                    symbol: "mountain.2",
                    route: .legs(.rail)
                )
            }
        }
    }

    private func roadAndSeaCard(_ stats: RoadAndSeaStatistics) -> some View {
        let system = model.rules.unitSystem
        return StatCardList {
            if stats.roadTripLegs > 0 {
                StatRow(
                    "Distance driven",
                    Format.distance(stats.kilometresDriven, system),
                    symbol: "car",
                    detail: stats.roadInput.caveat(counting: "road trips")
                        ?? Format.ordinalCount(stats.roadTripLegs, "road trip"),
                    route: .legs(.roadTrip)
                )
            }
            if stats.ferriesTaken > 0 {
                StatRow(
                    "Ferries taken",
                    "\(stats.ferriesTaken)",
                    symbol: "ferry",
                    detail: stats.seaInput.caveat(counting: "ferries")
                        ?? "\(Format.distance(stats.seaKilometres, system)) at sea",
                    route: .legs(.ferry)
                )
            }
            if let longest = stats.longestSeaCrossing {
                StatRow<LogRoute>(
                    title: "Longest sea crossing",
                    value: Format.distance(longest.distanceKm, system),
                    symbol: "water.waves",
                    detail: "\(longest.origin.shortName) → \(longest.destination.shortName)",
                    destination: model.journeyID(containing: longest.id).map(LogRoute.journey)
                )
            }
            namedRow("Ships sailed on", stats.ships, symbol: "sailboat", route: .legs(.ferry))
            if !stats.passes.isEmpty {
                StatRow(
                    "Mountain passes",
                    "\(stats.passes.count)",
                    symbol: "mountain.2",
                    detail: stats.passes.prefix(3).map(\.name).joined(separator: ", ")
                        + (stats.passes.count > 3 ? "…" : ""),
                    route: .visits(title: "Mountain passes", ids: stats.passVisitIDs)
                )
            }
        }
    }

    /// A count of names with the first few beneath it, left out while there are none.
    @ViewBuilder
    private func namedRow(
        _ title: String,
        _ names: Set<String>,
        symbol: String,
        route: StatsRoute
    ) -> some View {
        if !names.isEmpty {
            StatRow(
                title,
                "\(names.count)",
                symbol: symbol,
                detail: names.sorted().prefix(4).joined(separator: ", ")
                    + (names.count > 4 ? "…" : ""),
                route: route
            )
        }
    }
}

// MARK: - Punctuality

/// How late things ran, by mode and by operator (§5.7, "Punctuality").
private struct PunctualitySection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let punctuality = model.shownStatistics.punctuality
        let journeys = model.shownStatistics.journeys
        if punctuality.input.used > 0 || journeys.multiLegJourneys > 0 {
            StatsSection(title: "Punctuality and connections", symbol: "clock") {
                if punctuality.input.used > 0 {
                    StatCardList { rows(punctuality) }
                }
                if journeys.multiLegJourneys > 0 {
                    StatCardList {
                        StatRow(
                            "Multi-leg journeys",
                            "\(journeys.multiLegJourneys)",
                            symbol: "point.3.connected.trianglepath.dotted",
                            route: .legFilter(.connections)
                        )
                        StatRow(
                            "Connections missed",
                            "\(journeys.connectionsMissed)",
                            symbol: "exclamationmark.arrow.triangle.2.circlepath",
                            route: .legFilter(.connections)
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rows(_ punctuality: PunctualityStatistics) -> some View {
        if let average = punctuality.averageDelayMinutes {
            StatRow(
                "Average arrival",
                Format.delay(minutes: average),
                symbol: "clock.badge.exclamationmark",
                detail: punctuality.input.caveat(counting: "legs") ?? byMode(punctuality),
                route: .legFilter(.timed)
            )
        }
        if let share = punctuality.onTimeShare {
            StatRow(
                "On time",
                Format.percent(share, digits: 0),
                symbol: "checkmark.circle",
                detail: "Within \(PunctualityStatistics.onTimeToleranceMinutes) minutes",
                route: .legFilter(.timed)
            )
        }
        if let best = punctuality.mostPunctualOperator {
            StatRow(
                "Most punctual",
                best.name,
                symbol: "hand.thumbsup",
                detail: Format.delay(minutes: best.averageDelayMinutes),
                route: .operators
            )
        }
        if let worst = punctuality.leastPunctualOperator,
           worst != punctuality.mostPunctualOperator {
            StatRow(
                "Least punctual",
                worst.name,
                symbol: "tortoise",
                detail: Format.delay(minutes: worst.averageDelayMinutes),
                route: .operators
            )
        }
        if !punctuality.operators.isEmpty {
            StatRow(
                "Operators timed",
                "\(punctuality.operators.count)",
                symbol: "list.number",
                detail: "Average delay for each",
                route: .operators
            )
        }
        if let minutes = punctuality.worstDelayMinutes, minutes > 0 {
            StatRow(
                "Worst delay",
                Format.duration(minutes: minutes),
                symbol: "exclamationmark.triangle",
                detail: punctuality.worstDelay
                    .map { "\($0.origin.shortName) → \($0.destination.shortName)" },
                route: .legFilter(.timed)
            )
        }
    }

    /// "Flight +12 min · Rail +3 min", when more than one mode was timed.
    private func byMode(_ punctuality: PunctualityStatistics) -> String? {
        guard punctuality.averageDelayByMode.count > 1 else { return nil }
        return punctuality.averageDelayByMode
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.displayName) \(Format.delay(minutes: $0.value))" }
            .joined(separator: " · ")
    }
}

extension AppModel {
    /// The journey a leg belongs to.
    func journeyID(containing legID: UUID) -> UUID? {
        log.journeys.first { $0.legs.contains { $0.id == legID } }?.id
    }
}

private extension RoadAndSeaStatistics {
    var hasAnything: Bool {
        roadTripLegs > 0 || ferriesTaken > 0 || !passes.isEmpty
    }
}
