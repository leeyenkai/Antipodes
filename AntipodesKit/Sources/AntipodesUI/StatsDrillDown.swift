import AntipodesCore
import AntipodesStats
import SwiftUI

/// What a number rests on (§7, "Every number MUST be tappable to show the visits
/// behind it"). Each list applies the same rules as the number it came from.
struct StatsDrillDown: View {
    @Environment(AppModel.self) private var model
    let route: StatsRoute

    var body: some View {
        switch route {
        case .countries: CountryListView()
        case let .places(kind): PlaceListView(kind: kind)
        case .capitals: PlaceListView(kind: .city, filter: .capitals)
        case .unesco: PlaceListView(kind: .landmark, filter: .unesco)
        case .personality: PersonalityDetailView()
        case let .legs(mode): LegListView(mode: mode)
        case .carbon: LegListView(mode: nil, showsCarbon: true)
        case .repeats: RepeatVisitsView()
        case .gaps: CountryGapsView()
        case let .year(year): YearInReviewView(year: year)
        }
    }
}

/// Every country visited, under the user's rules, with the visits behind each.
struct CountryListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let coverage = model.statistics.coverage
        List {
            Section {
                ForEach(coverage.countriesSortedByName, id: \.code) { country in
                    NavigationLink(value: LogRoute.country(country.code)) {
                        HStack {
                            Text(Format.flag(country.code)).font(.title2)
                            VStack(alignment: .leading) {
                                Text(country.name)
                                if let first = coverage.firstDayByCountry[country.code] {
                                    Text("First visited \(Format.day(first))")
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
        let ids = Set(model.statistics.coverage.visitIDsByCountry[countryCode] ?? [])
        let visits = model.log.visits.filter { ids.contains($0.id) }.sorted { $0.date > $1.date }
        let facts = model.catalogue.countries[countryCode]
        List {
            Section {
                HStack(spacing: 14) {
                    Text(Format.flag(countryCode)).font(.system(size: 54))
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
                    NavigationLink(value: LogRoute.visit(first.id)) {
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
        let coverage = model.statistics.coverage
        var groups: [String: (place: PlaceReference, visits: [Visit])] = [:]
        for visit in model.log.visits where model.rules.countsTowardsCoverage(visit.visitType) {
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
            for leg in model.log.allLegs where leg.mode == .flight {
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

/// Legs, optionally of one mode, with their distance or carbon.
struct LegListView: View {
    @Environment(AppModel.self) private var model
    let mode: TravelMode?
    var showsCarbon = false

    var body: some View {
        let carbon = model.statistics.carbon
        let rows = model.log.journeys.flatMap { journey in
            journey.legs.filter { mode == nil || $0.mode == mode }
                .map { (journey: journey, leg: $0) }
        }
        .sorted { $0.leg.date > $1.leg.date }
        List {
            ForEach(rows, id: \.leg.id) { row in
                NavigationLink(value: LogRoute.journey(row.journey.id)) {
                    HStack(spacing: 12) {
                        SymbolTile(
                            systemName: row.leg.mode.symbolName,
                            tint: Palette.mode(row.leg.mode)
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(row.leg.origin.shortName) → \(row.leg.destination.shortName)")
                            Text(row.leg.date.displayText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if showsCarbon {
                                Text(carbon.kgByLeg[row.leg.id]
                                    .map { Format.carbon(kilograms: $0) } ?? "—")
                                if let saved = carbon.savedByLeg[row.leg.id], saved > 0 {
                                    Text("saved \(Format.carbon(kilograms: saved))")
                                        .font(.caption2)
                                        .foregroundStyle(Palette.visited)
                                }
                            } else {
                                Text(Format.distance(
                                    row.leg.distanceKm,
                                    model.rules.unitSystem,
                                    approximate: row.leg.distanceSource
                                        .isApproximate
                                ))
                                if let minutes = row.leg.durationMinutes {
                                    Text(Format.duration(minutes: minutes))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .font(.subheadline.monospacedDigit())
                    }
                }
                .swipeActions(edge: .leading) {
                    Button("Ride Again", systemImage: "arrow.uturn.forward") {
                        model.rideAgain(row.leg, tripID: row.journey.tripID)
                    }
                    .tint(Palette.visited)
                }
            }
            if rows.isEmpty {
                ContentUnavailableView("No journeys", systemImage: mode?.symbolName ?? "airplane")
            }
        }
        .navigationTitle(showsCarbon ? "Carbon by leg" : (mode?.displayName ?? "All legs"))
    }
}

/// The personality and every score behind it (R-PERS-2).
struct PersonalityDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let themes = model.statistics.themes
        List {
            if let personality = themes.personality {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            personality.archetype.name,
                            systemImage: personality.archetype.symbolName
                        )
                        .font(.title.weight(.bold))
                        .foregroundStyle(Palette.archetype(personality.archetype))
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
                ForEach(themes.shares) { share in
                    LabeledContent(share.label, value: Format.percent(share.share))
                }
                if let caveat = themes.input.caveat(counting: "landmarks") {
                    CaveatLabel(text: caveat)
                }
            }
        }
        .navigationTitle("Travel personality")
    }
}

struct RepeatVisitsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(model.statistics.time.repeatVisits, id: \.place.id) { repeated in
            HStack {
                PlaceRow(place: repeated.place)
                Spacer()
                Text("\(repeated.visitCount)×")
                    .font(.headline.monospacedDigit())
            }
        }
        .navigationTitle("Places returned to")
    }
}

struct CountryGapsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(model.statistics.time.countryGaps, id: \.countryCode) { gap in
            NavigationLink(value: LogRoute.country(gap.countryCode)) {
                HStack {
                    Text(Format.flag(gap.countryCode)).font(.title2)
                    VStack(alignment: .leading) {
                        Text(gap.countryName)
                        Text("Last there \(Format.day(gap.lastVisited))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(gap.daysSince >= 365 ? "\(gap.daysSince / 365)y" : "\(gap.daysSince)d")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Time since each country")
    }
}
