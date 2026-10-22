import AntipodesCore
import AntipodesStats
import SwiftUI

/// What a number rests on (§7, "Every number MUST be tappable to show the visits
/// behind it"). Each list applies the same rules as the number it came from.
struct StatsDrillDown: View {
    @Environment(AppModel.self) private var model
    let route: StatsRoute

    var body: some View {
        destination
            .modifier(DrillDownShare(card: shareCard))
    }

    @ViewBuilder
    private var destination: some View {
        switch route {
        case .countries: CountryListView()
        case let .places(kind): PlaceListView(kind: kind)
        case .capitals: PlaceListView(kind: .city, filter: .capitals)
        case .unesco: PlaceListView(kind: .landmark, filter: .unesco)
        case .personality: PersonalityDetailView()
        case let .legs(mode): LegListView(filter: .mode(mode))
        case let .legFilter(filter): LegListView(filter: filter)
        case let .carbon(mode): LegListView(filter: .mode(mode), showsCarbon: true)
        case let .ranked(list): RankedPlacesView(list: list)
        case let .grouped(list): GroupedAttributeView(list: list)
        case .operators: OperatorPunctualityView()
        case .timeByMode: TimeByModeView()
        case .temperatures: VisitTemperatureList()
        case .transitSystems: TransitSystemsView()
        case let .transitSystem(id): TransitSystemDetailView(systemID: id)
        case .repeats: RepeatVisitsView()
        case .gaps: CountryGapsView()
        case .continents: ContinentListView()
        case .trips: TripStatsList()
        case let .visits(title, ids): VisitListView(title: title, ids: ids)
        }
    }
}

extension StatsDrillDown {
    /// The number this list explains, as a card to share — or nothing, for a list
    /// that is not one number.
    private var shareCard: ShareCard? {
        let statistics = model.shownStatistics
        let system = model.rules.unitSystem
        switch route {
        case .countries:
            return .stat(
                title: "countries visited",
                value: "\(statistics.coverage.listedCountriesVisited)",
                detail: "\(Format.percent(statistics.coverage.worldFraction)) of the world",
                symbol: "flag.fill"
            )
        case let .places(kind):
            let count = switch kind {
            case .city: statistics.coverage.citiesVisited
            case .landmark: statistics.coverage.landmarksVisited
            case .airport: statistics.flights.airportsVisited
            case .region: statistics.coverage.regionsVisited
            default: 0
            }
            guard count > 0 else { return nil }
            return .stat(
                title: kind.pluralName.lowercased(),
                value: "\(count)",
                detail: nil,
                symbol: kind.symbolName
            )
        case .capitals:
            return .stat(
                title: "capitals",
                value: "\(statistics.coverage.capitalsVisited)",
                detail: nil,
                symbol: "building.columns.fill"
            )
        case .unesco:
            return .stat(
                title: "UNESCO World Heritage Sites",
                value: "\(statistics.coverage.unescoSitesVisited)",
                detail: nil,
                symbol: "seal.fill"
            )
        case let .legs(mode):
            let kilometres = mode
                .map { statistics.distance.kilometresByMode[$0] ?? 0 } ?? statistics.distance
                .totalKm
            return .stat(
                title: mode.map { "by \($0.displayName.lowercased())" } ?? "travelled",
                value: Format.distance(kilometres, system),
                detail: mode == nil
                    ? "\(Format.multiple(statistics.distance.timesRoundTheEarth)) round the Earth" :
                    nil,
                symbol: mode?.symbolName ?? "globe"
            )
        case .carbon:
            let total = statistics.carbon.totalKg
            guard total > 0 else { return nil }
            return .stat(
                title: "CO₂e, estimated",
                value: Format.carbon(kilograms: total),
                detail: statistics.carbon.shortCredit,
                symbol: "leaf.fill"
            )
        case .personality:
            return statistics.themes.personality == nil ? nil : .personality
        case .repeats, .gaps, .continents, .trips, .visits, .legFilter, .ranked, .grouped,
             .operators, .timeByMode, .temperatures, .transitSystems, .transitSystem:
            return nil
        }
    }
}

/// A share button for a drill-down that stands for one number.
private struct DrillDownShare: ViewModifier {
    let card: ShareCard?

    func body(content: Content) -> some View {
        if let card {
            content.shareCardButton { card }
        } else {
            content
        }
    }
}

/// Every country visited, under the user's rules, with the visits behind each.
struct CountryListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let coverage = model.shownStatistics.coverage
        List {
            Section {
                ForEach(coverage.countriesSortedByName, id: \.code) { country in
                    NavigationLink(value: LogRoute.country(country.code)) {
                        HStack {
                            Text(Format.flag(country.code)).font(.title2)
                            VStack(alignment: .leading) {
                                Text(country.name)
                                if let first = coverage.firstVisitByCountry[country.code] {
                                    Text("First visited \(first.displayText)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if coverage.unlistedCountryCodes.contains(country.code) {
                                Text("Not on list")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(coverage.visitIDsByCountry[country.code]?.count ?? 0)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("""
                    \(coverage.listedCountriesVisited) of \(coverage.worldCountryCount) \
                    \(coverage.countryList.displayName). Change the list in Settings.
                    """)
                    if let caveat = coverage.input.caveat {
                        Text(caveat)
                    }
                }
            }
        }
        .navigationTitle("Countries")
    }
}

/// One country: every visit in it that counts, and what else is known about it.
struct CountryDetailView: View {
    @Environment(AppModel.self) private var model
    let countryCode: String

    var body: some View {
        let ids = Set(model.shownStatistics.coverage.visitIDsByCountry[countryCode] ?? [])
        let visits = model.shownLog.visits.filter { ids.contains($0.id) }
            .sorted { $0.date > $1.date }
        let facts = model.catalogue.countries[countryCode]
        List {
            Section {
                HStack(spacing: 14) {
                    Text(Format.flag(countryCode)).font(.icon(54))
                    VStack(alignment: .leading) {
                        Text(facts?.name ?? countryCode).font(.title2.weight(.bold))
                        Text(facts?.continent?.displayName ?? "").foregroundStyle(.secondary)
                    }
                }
                if let capital = facts?.capitalName {
                    DetailRow(title: "Capital", value: capital)
                }
                if let language = facts?.primaryLanguage {
                    DetailRow(title: "Language", value: Format.languageName(language))
                }
                if let currency = facts?.currencyCode {
                    DetailRow(title: "Currency", value: Format.currencyName(currency))
                }
            }
            Section("Visits") {
                ForEach(visits) { visit in
                    NavigationLink(value: LogRoute.visit(visit.id)) {
                        VisitRow(visit: visit)
                    }
                }
            }
        }
        .navigationTitle(facts?.name ?? countryCode)
        .toolbarTitleDisplayMode(.inline)
        .globeFocus(.country(countryCode))
    }
}

/// Unique places of one kind, each with how often it was visited.
struct PlaceListView: View {
    enum Filter {
        case all
        case capitals
        case unesco
    }

    @Environment(AppModel.self) private var model
    let kind: PlaceKind
    var filter: Filter = .all

    var body: some View {
        let groups = grouped
        List {
            ForEach(groups, id: \.place.id) { group in
                if let first = group.visits.first {
                    // One visit opens itself; more open the list of them all.
                    navigationLink(group, first: first) {
                        HStack {
                            PlaceRow(place: group.place)
                            Spacer()
                            Text("\(group.visits.count)×")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } else {
                    PlaceRow(place: group.place, subtitle: "Flown through")
                }
            }
            if groups.isEmpty {
                ContentUnavailableView("None yet", systemImage: kind.symbolName)
            }
        }
        .navigationTitle(title)
    }

    @ViewBuilder
    private func navigationLink(
        _ group: (place: PlaceReference, visits: [Visit]),
        first: Visit,
        @ViewBuilder label: () -> some View
    ) -> some View {
        if group.visits.count == 1 {
            NavigationLink(value: LogRoute.visit(first.id), label: label)
        } else {
            NavigationLink(
                value: StatsRoute.visits(title: group.place.name, ids: group.visits.map(\.id)),
                label: label
            )
        }
    }

    private var title: String {
        switch filter {
        case .all: kind.pluralName
        case .capitals: "Capitals"
        case .unesco: "UNESCO-listed"
        }
    }

    /// Unique places reached by counted visits. A landmark implies its city, so the
    /// cities list includes the city of every landmark visited (R-MODEL-6).
    private var grouped: [(place: PlaceReference, visits: [Visit])] {
        let coverage = model.shownStatistics.coverage
        var groups: [String: (place: PlaceReference, visits: [Visit])] = [:]
        for visit in model.shownLog.visits
            where model.shownRules.countsTowardsCoverage(visit.visitType) {
            let place = visit.place
            switch kind {
            case .city:
                guard let city = place.impliedCityID else { continue }
                if filter == .capitals, !coverage.capitalCityIDs.contains(city) {
                    continue
                }
                let reference = place.kind == .city ? place : PlaceReference(
                    id: .database(.city, city),
                    kind: .city,
                    name: coverage.cityNames[city] ?? place.cityName ?? "City",
                    countryCode: place.countryCode,
                    countryName: place.countryName,
                    regionName: place.regionName
                )
                groups["\(city)", default: (reference, [])].visits.append(visit)
            case .region:
                guard let region = place.qualifiedRegionCode else { continue }
                let reference = PlaceReference(
                    id: place.id,
                    kind: .region,
                    name: place.regionName ?? region,
                    countryCode: place.countryCode,
                    countryName: place.countryName
                )
                groups[region, default: (reference, [])].visits.append(visit)
            default:
                guard place.kind == kind else { continue }
                if filter == .unesco, !coverage.unescoLandmarkIDs.contains(place.id) {
                    continue
                }
                groups[place.id.description, default: (place, [])].visits.append(visit)
            }
        }
        if kind == .airport {
            for leg in model.shownLog.allLegs where leg.mode == .flight {
                for end in [leg.origin, leg.destination]
                    where end.kind == .airport && groups[end.id.description] == nil {
                    groups[end.id.description] = (end, [])
                }
            }
        }
        return groups.values
            .sorted { $0.place.name.localizedStandardCompare($1.place.name) == .orderedAscending }
    }
}

/// The personality and every score behind it (R-PERS-2).
struct PersonalityDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let themes = model.shownStatistics.themes
        List {
            if let personality = themes.personality {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            personality.archetype.name,
                            systemImage: personality.archetype.symbolName
                        )
                        .font(.display(.title))
                        Text(personality.archetype.summary)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    ForEach(personality.scores) { score in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(score.archetype.name, systemImage: score.archetype.symbolName)
                                Spacer()
                                Text(Format.percent(score.share, digits: 0))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: min(
                                1,
                                score.share / max(0.01, score.archetype.threshold)
                            ))
                            .tint(Palette.archetype(score.archetype))
                            Text(
                                """
                                Needs \(Format.percent(score.archetype.threshold, digits: 0)) of \
                                your theme mix
                                """
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("How it's worked out")
                } footer: {
                    Text("""
                    Each archetype is a group of landmark themes. Your personality is the group \
                    that most exceeds its threshold share of the themes of every landmark you've \
                    visited, each landmark counted once. If none reaches its threshold, you're a \
                    Wanderer. No machine learning — just these rules.
                    """)
                }
            }
            Section("Your theme mix") {
                // Each theme opens the landmarks that carry it.
                ForEach(themes.shares) { share in
                    NavigationLink(value: StatsRoute.visits(
                        title: share.label,
                        ids: landmarkVisits(theme: share.theme)
                    )) {
                        LabeledContent(share.label, value: Format.percent(share.share))
                    }
                }
                if let caveat = themes.input.caveat(counting: "landmarks") {
                    CaveatLabel(text: caveat)
                }
            }
        }
        .navigationTitle("Travel personality")
    }

    /// Visits that count, to landmarks tagged with a theme.
    private func landmarkVisits(theme: String) -> [UUID] {
        let gazetteer = model.gazetteer
        return model.shownLog.visits
            .filter {
                $0.place.kind == .landmark && model.shownRules.countsTowardsCoverage($0.visitType)
            }
            .filter { gazetteer.facts(for: $0.place.id)?.themes.contains(theme) ?? false }
            .map(\.id)
    }
}
