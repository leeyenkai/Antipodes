import AntipodesCore
import AntipodesStats
import Charts
import SwiftUI

// MARK: - Coverage

struct CoverageSection: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let coverage = model.shownStatistics.coverage
        let extremes = model.shownStatistics.extremes
        let system = model.rules.unitSystem
        StatsSection(title: "Coverage", symbol: "map", caveat: coverage.input.caveat) {
            StatCardList {
                StatRow(
                    "Countries",
                    "\(coverage.listedCountriesVisited)",
                    symbol: "flag",
                    detail: coverage.unlistedCountryCodes.isEmpty ? nil : """
                    +\(coverage.unlistedCountryCodes.count) not on the \
                    \(coverage.countryList.displayName) list
                    """,
                    route: .countries
                )
                StatRow(
                    "Share of the world",
                    Format.percent(coverage.worldFraction),
                    symbol: "percent",
                    detail: """
                    Measured against \(coverage.worldCountryCount) \
                    \(coverage.countryList.displayName)
                    """, route: .countries
                )
                StatRow(
                    "Regions",
                    "\(coverage.regionsVisited)",
                    symbol: "map",
                    route: .places(.region)
                )
                StatRow(
                    "Cities",
                    "\(coverage.citiesVisited)",
                    symbol: "building.2",
                    route: .places(.city)
                )
                StatRow("Capitals", "\(coverage.capitalsVisited)", symbol: "star", route: .capitals)
                StatRow(
                    "Landmarks",
                    "\(coverage.landmarksVisited)",
                    symbol: "building.columns",
                    route: .places(.landmark)
                )
                StatRow(
                    "UNESCO-listed landmarks",
                    "\(coverage.unescoSitesVisited)",
                    symbol: "laurel.leading",
                    route: .unesco
                )
                StatRow(
                    "Airports",
                    "\(model.shownStatistics.flights.airportsVisited)",
                    symbol: "airplane.departure",
                    route: .places(.airport)
                )
            }
            StatCardList {
                extremeRow("Northernmost", extremes.northernmost, symbol: "arrow.up")
                extremeRow("Southernmost", extremes.southernmost, symbol: "arrow.down")
                extremeRow("Easternmost", extremes.easternmost, symbol: "arrow.right")
                extremeRow("Westernmost", extremes.westernmost, symbol: "arrow.left")
                if let highest = extremes.highest {
                    StatRow<LogRoute>(
                        title: "Highest",
                        value: Format.elevation(highest.elevationM, system),
                        symbol: "mountain.2",
                        detail: [
                            highest.visit.place.name,
                            extremes.elevationInput.caveat(counting: "places"),
                        ].compactMap(\.self).joined(separator: "\n"),
                        destination: .visit(highest.visit.id)
                    )
                }
                if let lowest = extremes.lowest, lowest.visit != extremes.highest?.visit {
                    StatRow<LogRoute>(
                        title: "Lowest",
                        value: Format.elevation(lowest.elevationM, system),
                        symbol: "water.waves",
                        detail: lowest.visit.place.name,
                        destination: .visit(lowest.visit.id)
                    )
                }
            }
            AntipodeCard()
        }
    }

    @ViewBuilder
    private func extremeRow(_ title: String, _ visit: Visit?, symbol: String) -> some View {
        if let visit {
            StatRow<LogRoute>(
                title: title,
                value: visit.place.name,
                symbol: symbol,
                detail: visit.place.coordinate?.displayText,
                destination: .visit(visit.id)
            )
        }
    }
}

/// The stat the app is named after: the point on the far side of the world from home.
private struct AntipodeCard: View {
    @Environment(AppModel.self) private var model
    @State private var isPickingHome = false

    var body: some View {
        let extremes = model.shownStatistics.extremes
        VStack(alignment: .leading, spacing: 8) {
            Label("Your antipode", systemImage: "circle.circle")
                .font(.headline)
            if let home = model.home, let antipode = extremes.antipodeOfHome {
                Text("Directly through the Earth from \(home.name) is \(antipode.displayText).")
                    .foregroundStyle(.secondary)
                if let nearest = extremes.nearestToAntipodeOfHome,
                   let gap = extremes.nearestToAntipodeKm {
                    Text("""
                    The closest you've been is \(nearest.place.name), \
                    \(Format.distance(gap, model.rules.unitSystem)) from it.
                    """)
                }
                if let furthest = extremes.furthestFromHome,
                   let distance = extremes.furthestFromHomeKm {
                    Text("""
                    Furthest from home: \(furthest.place.name), \
                    \(Format.distance(distance, model.rules.unitSystem)).
                    """)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("""
                Set your home to find the point on exactly the other side of the world, and \
                how close you've been to it.
                """)
                .foregroundStyle(.secondary)
                // Content, not a floating control: a bordered button, not glass.
                Button("Set Home", systemImage: "house") { isPickingHome = true }
                    .buttonStyle(.bordered)
            }
        }
        .card()
        .sheet(isPresented: $isPickingHome) {
            PlacePickerSheet(
                title: "Home",
                prompt: "Search your home city",
                kinds: [.city],
                fixedKinds: [.city]
            ) {
                model.home = $0
            }
        }
    }
}

// MARK: - Distance

struct DistanceSection: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let statistics = model.shownStatistics
        let distance = statistics.distance
        let flights = statistics.flights
        let journeys = statistics.journeys
        let system = model.rules.unitSystem
        StatsSection(
            title: "Distance and routes",
            symbol: "point.topleft.down.to.point.bottomright.curvepath",
            caveat: distance.input.caveat
        ) {
            if !distance.kilometresByMode.isEmpty {
                ModeDistanceChart(distance: distance, system: system)
                    .card()
            }
            StatCardList {
                StatRow(
                    "Total",
                    Format.distance(distance.totalKm, system),
                    symbol: "sum",
                    detail: approximateDetail(distance, system),
                    route: .legs(nil)
                )
                StatRow(
                    "Round the Earth",
                    Format.multiple(distance.timesRoundTheEarth),
                    symbol: "globe", route: .legs(nil)
                )
                StatRow(
                    "To the Moon",
                    Format.percent(distance.totalKm / 384_400),
                    symbol: "moon",
                    route: .legs(nil)
                )
                if let longest = distance.longestLeg {
                    StatRow<LogRoute>(
                        title: "Longest leg",
                        value: Format.distance(longest.distanceKm, system),
                        symbol: "arrow.left.and.right",
                        detail: "\(longest.origin.shortName) → \(longest.destination.shortName)",
                        destination: journeyRoute(for: longest)
                    )
                }
                if let longest = distance.longestJourney, longest.legs.count > 1 {
                    StatRow<LogRoute>(
                        title: "Longest journey",
                        value: Format.distance(longest.totalDistanceKm, system),
                        symbol: "point.3.connected.trianglepath.dotted",
                        detail: longest.displayTitle,
                        destination: .journey(longest.id)
                    )
                }
                if journeys.totalMinutes > 0 {
                    StatRow(
                        "Time travelling",
                        Format.duration(minutes: journeys.totalMinutes),
                        symbol: "clock",
                        detail: journeys.durationInput.caveat(counting: "legs")
                            ?? hoursByMode(journeys),
                        route: .timeByMode
                    )
                }
                if let busiest = journeys.busiestDay {
                    StatRow(
                        "Most legs in a day",
                        "\(busiest.legs)",
                        symbol: "calendar",
                        detail: [
                            Format.day(busiest.day),
                            journeys.dayInput.caveat(counting: "legs"),
                        ].compactMap(\.self).joined(separator: "\n"),
                        route: .legFilter(.onDay(busiest.day))
                    )
                }
                if let varied = journeys.mostVariedJourney {
                    StatRow<LogRoute>(
                        title: "Most modes in one journey",
                        value: "\(varied.modes.count)",
                        symbol: "arrow.triangle.branch",
                        detail: varied.displayTitle,
                        destination: .journey(varied.id)
                    )
                }
                if !journeys.countriesOverland.isEmpty {
                    StatRow(
                        "Countries overland",
                        "\(journeys.countriesOverland.count)",
                        symbol: "car",
                        detail: """
                        \(Format.ordinalCount(journeys.bordersCrossedOverland, "border")) crossed \
                        by land
                        """, route: .legFilter(.overland)
                    )
                }
            }
            if flights.flightCount > 0 {
                StatCardList {
                    StatRow(
                        "Flights",
                        "\(flights.flightCount)",
                        symbol: "airplane",
                        route: .legs(.flight)
                    )
                    if journeys.flightMinutes > 0 {
                        StatRow(
                            "Flight hours",
                            Format.hours(minutes: journeys.flightMinutes),
                            symbol: "clock", route: .legs(.flight)
                        )
                    }
                    StatRow(
                        "Airports",
                        "\(flights.airportsVisited)",
                        symbol: "airplane.departure",
                        route: .places(.airport)
                    )
                    StatRow(
                        "Airlines",
                        "\(flights.airlineNames.count)",
                        symbol: "building",
                        detail: flights.airlineNames.sorted().prefix(4).joined(separator: ", "),
                        route: .legs(.flight)
                    )
                    StatRow(
                        "Aircraft types",
                        "\(flights.aircraftTypes.count)",
                        symbol: "airplane.circle",
                        detail: flights.aircraftTypes.sorted().prefix(3).joined(separator: ", "),
                        route: .legs(.flight)
                    )
                    StatRow(
                        "Average flight",
                        Format.distance(flights.averageFlightKm, system),
                        symbol: "divide",
                        detail: flights.input.caveat(counting: "flights"), route: .legs(.flight)
                    )
                }
            }
        }
    }

    private func approximateDetail(
        _ distance: DistanceStatistics,
        _ system: UnitSystem
    ) -> String? {
        guard distance.approximateLegCount > 0 else { return nil }
        return "\(Format.distance(distance.approximateKm, system)) of it on straight-line estimates"
    }

    /// "Flight 42 h · Rail 12 h", the two modes with the most time.
    private func hoursByMode(_ journeys: JourneyStatistics) -> String? {
        guard journeys.minutesByMode.count > 1 else { return nil }
        return journeys.minutesByMode
            .sorted { $0.value > $1.value }
            .prefix(2)
            .map { "\($0.key.displayName) \(Format.hours(minutes: $0.value))" }
            .joined(separator: " · ")
    }

    private func journeyRoute(for leg: JourneyLeg) -> LogRoute? {
        model.shownLog.journeys.first { $0.legs.contains { $0.id == leg.id } }
            .map { .journey($0.id) }
    }
}

private struct ModeDistanceChart: View {
    let distance: DistanceStatistics
    let system: UnitSystem

    var body: some View {
        let rows = distance.modesSortedByDistance
        Chart(rows, id: \.mode) { row in
            BarMark(
                x: .value("Distance", system.distance(fromKilometres: row.kilometres)),
                y: .value("Mode", row.mode.displayName)
            )
            .foregroundStyle(Palette.mode(row.mode))
            .cornerRadius(6)
            .annotation(position: .trailing) {
                Text(Format.distance(row.kilometres, system))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxis(.hidden)
        .frame(height: CGFloat(rows.count) * 34 + 10)
        .accessibilityLabel("Distance by mode")
    }
}
