import AntipodesCore
import AntipodesStats
import Charts
import SwiftUI

// MARK: - Place attributes

struct AttributesSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let attributes = model.statistics.attributes
        let system = model.rules.unitSystem
        StatsSection(title: "Place attributes", symbol: "building.columns") {
            StatCardList {
                if let average = attributes.averageLandmarkAgeYears {
                    StatRow(
                        "Average landmark age",
                        Format.years(average),
                        symbol: "hourglass",
                        detail: attributes.landmarkAgeInput.caveat(counting: "landmarks")
                            ?? attributes.medianLandmarkAgeYears
                            .map { "Median \(Format.years($0))" }, route: .places(.landmark)
                    )
                }
                if let oldest = attributes.oldestLandmark {
                    StatRow(
                        "Oldest",
                        Format.year(Int(oldest.value)),
                        symbol: "scroll",
                        detail: oldest.place.name, route: .places(.landmark)
                    )
                }
                if let newest = attributes.newestLandmark, newest != attributes.oldestLandmark {
                    StatRow(
                        "Newest",
                        Format.year(Int(newest.value)),
                        symbol: "sparkle",
                        detail: newest.place.name, route: .places(.landmark)
                    )
                }
                if let population = attributes.averageCityPopulation {
                    StatRow(
                        "Average city",
                        Format.compact(population) + " people",
                        symbol: "person.3",
                        detail: attributes.cityPopulationInput.caveat(counting: "cities")
                            ?? attributes.largestCity.map { "Largest: \($0.place.name)" },
                        route: .places(.city)
                    )
                }
                if let smallest = attributes.smallestCity, attributes.cityPopulationInput.used > 1 {
                    StatRow(
                        "Smallest city",
                        Format.compact(smallest.value) + " people",
                        symbol: "house",
                        detail: smallest.place.name, route: .places(.city)
                    )
                }
                if let elevation = attributes.averageElevationM {
                    StatRow(
                        "Average elevation",
                        Format.elevation(elevation, system),
                        symbol: "mountain.2",
                        detail: attributes.highestPlace
                            .map {
                                "Highest: \($0.place.name), \(Format.elevation($0.value, system))"
                            }, route: .places(.city)
                    )
                }
                StatRow(
                    "Time zones",
                    "\(attributes.timeZones.count)",
                    symbol: "clock",
                    detail: attributes.timeZoneInput.caveat(counting: "places"), route: .countries
                )
                StatRow(
                    "Languages",
                    "\(attributes.languageCodes.count)",
                    symbol: "character.bubble",
                    detail: names(attributes.languageCodes, Format.languageName), route: .countries
                )
                StatRow(
                    "Currencies",
                    "\(attributes.currencyCodes.count)",
                    symbol: "banknote",
                    detail: attributes.currencyCodes.sorted().prefix(6)
                        .joined(separator: " · "), route: .countries
                )
            }
            Text("""
            Temperature in the month you visited needs climate data that hasn't been \
            licence-cleared yet, so it isn't shown rather than guessed.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func names(_ codes: Set<String>, _ name: (String) -> String) -> String? {
        guard !codes.isEmpty else { return nil }
        return codes.map(name).sorted().prefix(5)
            .joined(separator: ", ") + (codes.count > 5 ? "…" : "")
    }
}

// MARK: - Time and patterns

struct PatternsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let time = model.statistics.time
        StatsSection(title: "Time and patterns", symbol: "calendar") {
            if !time.visitsByYear.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Places visited per year")
                        .font(.subheadline.weight(.semibold))
                    YearChart(
                        values: time.visitsByYear.mapValues(Double.init),
                        tint: Palette.visited
                    )
                    if let caveat = time.yearInput.caveat(counting: "visits") {
                        CaveatLabel(text: caveat)
                    }
                }
                .card()
            }
            if !time.visitsByMonth.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Seasonality")
                        .font(.subheadline.weight(.semibold))
                    SeasonalityChart(byMonth: time.visitsByMonth)
                    if let caveat = time.monthInput.caveat(counting: "visits") {
                        CaveatLabel(text: caveat)
                    }
                }
                .card()
            }
            StatCardList {
                if time.totalDaysAway > 0 {
                    StatRow(
                        "Days away",
                        "\(time.totalDaysAway)",
                        symbol: "sun.max",
                        detail: daysAwayDetail(time), route: .trips
                    )
                }
                if !time.tripsByYear.isEmpty {
                    StatRow(
                        "Trips",
                        "\(time.tripsByYear.values.reduce(0, +))",
                        symbol: "suitcase",
                        detail: time.tripsByYear.sorted { $0.key > $1.key }.prefix(3)
                            .map { "\($0.value) in \($0.key)" }.joined(separator: ", "),
                        route: .trips
                    )
                }
                if let average = time.averageTripDays {
                    StatRow(
                        "Average trip",
                        Format.ordinalCount(Int(average.rounded()), "day"),
                        symbol: "ruler",
                        detail: time.longestTrip
                            .map { "Longest: \(Format.ordinalCount($0.days, "day"))" },
                        route: .trips
                    )
                }
                if let busiest = time.busiestMonth {
                    StatRow(
                        "Busiest month",
                        "\(Format.monthName(busiest.month)) \(String(busiest.year))",
                        symbol: "flame",
                        detail: Format.ordinalCount(busiest.visits, "visit"),
                        route: .visits(
                            title: "\(Format.monthName(busiest.month)) \(String(busiest.year))",
                            ids: model.log.visits.filter {
                                $0.date.year == busiest.year && $0.date.startMonth == busiest.month
                                    && model.rules.countsTowardsCoverage($0.visitType)
                            }.map(\.id)
                        )
                    )
                }
                if !time.repeatVisits.isEmpty {
                    StatRow(
                        "Places returned to",
                        "\(time.repeatVisits.count)",
                        symbol: "arrow.triangle.2.circlepath",
                        detail: time.repeatVisits.first
                            .map { "Most: \($0.place.name), \($0.visitCount)×" },
                        route: .repeats
                    )
                }
                if let gap = time.countryGaps.first {
                    StatRow(
                        "Longest since",
                        "\(Format.flag(gap.countryCode)) \(gap.countryName)",
                        symbol: "hourglass.bottomhalf.filled",
                        detail: [
                            "\(Format.elapsed(days: gap.daysSince)) — last there "
                                + Format.day(gap.lastVisited),
                            time.gapInput.caveat(counting: "visits"),
                        ].compactMap(\.self).joined(separator: "\n"),
                        route: .gaps
                    )
                }
            }
            OnThisDayCard(entries: time.onThisDay)
        }
    }

    private func daysAwayDetail(_ time: TimeStatistics) -> String? {
        let recent = time.daysAwayByYear.sorted { $0.key > $1.key }.prefix(3)
            .map { "\($0.value) in \($0.key)" }
        let caveat = time.daysAwayInput.caveat(counting: "records")
        return ([recent.joined(separator: ", ")] + [caveat].compactMap(\.self))
            .joined(separator: "\n")
    }
}

struct YearChart: View {
    let values: [Int: Double]
    var tint: Color = Palette.visited

    var body: some View {
        let rows = values.sorted { $0.key < $1.key }
        Chart(rows, id: \.key) { year, value in
            BarMark(x: .value("Year", String(year)), y: .value("Count", value))
                .foregroundStyle(tint.gradient)
                .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6))
        }
        .frame(height: 150)
    }
}

private struct SeasonalityChart: View {
    let byMonth: [Int: Int]

    var body: some View {
        Chart(1 ... 12, id: \.self) { month in
            BarMark(
                x: .value("Month", Format.shortMonthName(month)),
                y: .value("Visits", byMonth[month] ?? 0)
            )
            .foregroundStyle(Palette.mode(.coach).gradient)
            .cornerRadius(4)
        }
        .frame(height: 140)
    }
}

private struct OnThisDayCard: View {
    @Environment(AppModel.self) private var model
    let entries: [OnThisDayEntry]

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("On this day", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                ForEach(entries.prefix(5)) { entry in
                    NavigationLink(value: route(entry)) {
                        HStack {
                            Text(title(entry))
                            Spacer()
                            Text(entry.yearsAgo == 1 ? "1 year ago" : "\(entry.yearsAgo) years ago")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
        }
    }

    private func title(_ entry: OnThisDayEntry) -> String {
        switch entry.record {
        case let .visit(visit): "\(visit.place.flag) \(visit.place.name)"
        case let .leg(leg): "\(leg.origin.shortName) → \(leg.destination.shortName)"
        }
    }

    private func route(_ entry: OnThisDayEntry) -> LogRoute {
        switch entry.record {
        case let .visit(visit): .visit(visit.id)
        case let .leg(leg):
            .journey(model.log.journeys.first { $0.legs.contains { $0.id == leg.id } }?.id ?? leg
                .id)
        }
    }
}

// MARK: - Culture and themes

struct ThemesSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let themes = model.statistics.themes
        if !themes.shares.isEmpty {
            StatsSection(
                title: "Culture and themes",
                symbol: "theatermasks",
                caveat: themes.input.caveat(counting: "landmarks")
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What you choose to see")
                        .font(.subheadline.weight(.semibold))
                    ThemeBars(shares: Array(themes.shares.prefix(8)))
                }
                .card()
                if !themes.landmarksByEra.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Across history")
                            .font(.subheadline.weight(.semibold))
                        EraChart(byEra: themes.landmarksByEra)
                        if let caveat = themes.eraInput.caveat(counting: "landmarks") {
                            CaveatLabel(text: caveat)
                        }
                    }
                    .card()
                }
            }
        }
    }
}

private struct EraChart: View {
    let byEra: [HistoricalEra: Int]

    var body: some View {
        Chart(HistoricalEra.allCases) { era in
            BarMark(x: .value("Era", era.displayName), y: .value("Landmarks", byEra[era] ?? 0))
                .foregroundStyle(Palette.archetype(.historian).gradient)
                .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel(orientation: .verticalReversed)
            }
        }
        .frame(height: 170)
    }
}

// MARK: - Year in review

struct YearInReviewTeaser: View {
    // Sized with the text, so the year and its summary never spill out of the tile.
    @ScaledMetric(relativeTo: .caption) private var tileWidth: CGFloat = 160
    @ScaledMetric(relativeTo: .caption) private var tileHeight: CGFloat = 110
    @Environment(AppModel.self) private var model
    @State private var presentedYear: YearItem?

    var body: some View {
        let years = YearInReview.availableYears(in: model.log)
        if !years.isEmpty {
            StatsSection(title: "Year in Review", symbol: "sparkles.rectangle.stack") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(years, id: \.self) { year in
                            Button {
                                presentedYear = YearItem(year: year)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(String(year))
                                        .font(.statValue(30))
                                    Text(summary(year))
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.75))
                                        .lineLimit(2)
                                }
                                .foregroundStyle(.white)
                                .padding(16)
                                .frame(
                                    width: tileWidth,
                                    height: tileHeight,
                                    alignment: .bottomLeading
                                )
                                .background(
                                    Palette.heroGradient,
                                    in: .rect(cornerRadius: 20, style: .continuous)
                                )
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(Palette.visited)
                                        .padding(12)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Year in review, \(year)")
                        }
                    }
                }
                .scrollClipDisabled()
            }
            .fullScreenCoverCompat(item: $presentedYear) { item in
                YearInReviewView(year: item.year)
            }
        }
    }

    private func summary(_ year: Int) -> String {
        let countries = Set(
            model.log.visits
                .filter { $0.date.year == year && model.rules.countsTowardsCoverage($0.visitType) }
                .compactMap(\.place.countryCode)
        ).count
        return "\(Format.ordinalCount(countries, "country", "countries"))"
    }
}

struct YearItem: Identifiable {
    let year: Int

    var id: Int {
        year
    }
}

extension View {
    /// Full screen on iPhone and iPad; a sheet on the Mac, which has no full-screen cover.
    func fullScreenCoverCompat<Item: Identifiable>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> some View
    ) -> some View {
        #if os(iOS)
            fullScreenCover(item: item, content: content)
        #else
            sheet(item: item, content: content)
        #endif
    }
}
