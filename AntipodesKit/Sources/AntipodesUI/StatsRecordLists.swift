import AntipodesCore
import AntipodesStats
import SwiftUI

/// Which legs a leg list shows, beyond a plain mode.
enum LegFilter: Hashable {
    case mode(TravelMode?)
    /// Sleepers and anything that ran overnight.
    case overnight
    /// Legs with a scheduled and an actual arrival, latest first.
    case timed
    /// Surface legs: everything but flights.
    case overland
    /// Every leg on one day.
    case onDay(CalendarDate)
    /// Legs of journeys with more than one leg.
    case connections

    func includes(_ leg: JourneyLeg, in journey: Journey) -> Bool {
        switch self {
        case let .mode(mode): mode == nil || leg.mode == mode
        case .overnight: leg.isOvernight
        case .timed: leg.times.arrivalDelayMinutes != nil
        case .overland: leg.mode != .flight
        case let .onDay(day): leg.date == .day(day)
        case .connections: journey.legs.count > 1
        }
    }

    var title: String {
        switch self {
        case let .mode(mode): mode?.displayName ?? "All legs"
        case .overnight: "Overnight"
        case .timed: "Arrivals"
        case .overland: "Overland"
        case let .onDay(day): Format.day(day)
        case .connections: "Multi-leg journeys"
        }
    }
}

/// Places ranked by one measured attribute.
enum RankedList: Hashable {
    case landmarkAge
    case elevation
    case population

    var title: String {
        switch self {
        case .landmarkAge: "Landmarks by age"
        case .elevation: "By elevation"
        case .population: "Cities by size"
        }
    }
}

/// Countries or places grouped under one attribute.
enum GroupedList: Hashable {
    case timeZones
    case languages
    case currencies
    case climateZones

    var title: String {
        switch self {
        case .timeZones: "Time zones"
        case .languages: "Main languages"
        case .currencies: "Currencies"
        case .climateZones: "Climate zones"
        }
    }
}

/// The places behind an attribute average, each with its own value (§7: every number
/// is tappable). Only places the database has a value for are listed; the caveat on
/// the figure says how many had none.
struct RankedPlacesView: View {
    @Environment(AppModel.self) private var model
    let list: RankedList

    var body: some View {
        let attributes = model.shownStatistics.attributes
        let system = model.rules.unitSystem
        let (rows, input): ([MeasuredPlace], StatInputSummary) = switch list {
        case .landmarkAge: (attributes.landmarksByYear, attributes.landmarkAgeInput)
        case .elevation: (attributes.placesByElevation, attributes.elevationInput)
        case .population: (attributes.citiesByPopulation, attributes.cityPopulationInput)
        }
        List {
            Section {
                ForEach(rows, id: \.place.id) { row in
                    NavigationLink(value: visitsRoute(for: row.place)) {
                        HStack {
                            PlaceRow(place: row.place)
                            Spacer(minLength: 8)
                            Text(value(row.value, system))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                if let caveat = input.caveat {
                    Text(caveat)
                }
            }
        }
        .navigationTitle(list.title)
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView("Nothing measured yet", systemImage: "ruler")
            }
        }
    }

    private func value(_ value: Double, _ system: UnitSystem) -> String {
        switch list {
        case .landmarkAge: Format.year(Int(value))
        case .elevation: Format.elevation(value, system)
        case .population: Format.compact(value)
        }
    }

    private func visitsRoute(for place: PlaceReference) -> StatsRoute {
        .visits(
            title: place.name,
            ids: model.shownLog.visits
                .filter { visit in
                    visit.place.id == place.id
                        || place.id.cityRow.map { $0 == visit.place.cityID } ?? false
                }
                .map(\.id)
        )
    }
}

/// Time zones with the places in each, or languages and currencies with the countries
/// that use them.
struct GroupedAttributeView: View {
    @Environment(AppModel.self) private var model
    let list: GroupedList

    var body: some View {
        let attributes = model.shownStatistics.attributes
        List {
            switch list {
            case .timeZones:
                ForEach(attributes.placesByTimeZone.keys.sorted(), id: \.self) { zone in
                    Section(zone.replacingOccurrences(of: "_", with: " ")) {
                        ForEach(attributes.placesByTimeZone[zone] ?? [], id: \.id) { place in
                            PlaceRow(place: place)
                        }
                    }
                }
            case .languages:
                countrySections(attributes.countriesByLanguage, name: Format.languageName)
            case .currencies:
                countrySections(attributes.countriesByCurrency) { code in
                    "\(Format.currencyName(code)) (\(code))"
                }
            case .climateZones:
                let climate = model.shownStatistics.climate
                ForEach(climate.zones) { zone in
                    Section {
                        ForEach(climate.placesByZone[zone] ?? [], id: \.id) { place in
                            PlaceRow(place: place)
                        }
                    } header: {
                        Text("\(zone.name) · \(zone.code)")
                    } footer: {
                        if zone == climate.zones.last {
                            Text("""
                            Köppen-Geiger zones worked out from TerraClimate's 1991–2020 \
                            averages, by the rules of Peel et al. (2007).
                            """)
                        }
                    }
                }
            }
        }
        .navigationTitle(list.title)
    }

    private func countrySections(
        _ groups: [String: [String]],
        name: @escaping (String) -> String
    ) -> some View {
        ForEach(groups.keys.sorted { name($0) < name($1) }, id: \.self) { key in
            Section(name(key)) {
                ForEach(groups[key] ?? [], id: \.self) { code in
                    NavigationLink(value: LogRoute.country(code)) {
                        Label {
                            Text(model.catalogue.countries[code]?.name ?? code)
                        } icon: {
                            Text(Format.flag(code))
                        }
                    }
                }
            }
        }
    }
}

/// Every operator with timed arrivals, by average delay, and each mode's average.
struct OperatorPunctualityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let punctuality = model.shownStatistics.punctuality
        List {
            if !punctuality.averageDelayByMode.isEmpty {
                Section("By mode") {
                    ForEach(
                        punctuality.averageDelayByMode.sorted { $0.value < $1.value },
                        id: \.key
                    ) { entry in
                        LabeledContent {
                            Text(Format.delay(minutes: entry.value)).monospacedDigit()
                        } label: {
                            Label(entry.key.displayName, systemImage: entry.key.symbolName)
                        }
                    }
                }
            }
            Section {
                ForEach(punctuality.operators.sorted {
                    ($0.averageDelayMinutes, $0.name) < ($1.averageDelayMinutes, $1.name)
                }) { record in
                    LabeledContent {
                        Text(Format.delay(minutes: record.averageDelayMinutes)).monospacedDigit()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.name)
                            Text(Format.ordinalCount(record.legs, "timed leg"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("By operator")
            } footer: {
                Text("""
                Arrival delay is the actual arrival minus the scheduled one, from the times \
                you entered. Operators need \(PunctualityStatistics.minimumLegsToRank) timed \
                legs to be called most or least punctual.
                """)
            }
        }
        .navigationTitle("Punctuality")
    }
}

/// Hours spent on each mode, from legs with a known duration.
struct TimeByModeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let journeys = model.shownStatistics.journeys
        List {
            Section {
                ForEach(journeys.minutesByMode.sorted { $0.value > $1.value }, id: \.key) { entry in
                    NavigationLink(value: StatsRoute.legs(entry.key)) {
                        LabeledContent {
                            Text(Format.hours(minutes: entry.value)).monospacedDigit()
                        } label: {
                            Label(entry.key.displayName, systemImage: entry.key.symbolName)
                        }
                    }
                }
            } footer: {
                if let caveat = journeys.durationInput.caveat(counting: "legs") {
                    Text(caveat)
                }
            }
        }
        .navigationTitle("Time travelling")
    }
}

private extension PlaceID {
    /// The city row this id names, for matching visits to landmarks in that city.
    var cityRow: Int64? {
        if case let .database(.city, row) = self {
            return row
        }
        return nil
    }
}

/// Every visit with the usual temperature of its month, warmest first.
struct VisitTemperatureList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let climate = model.shownStatistics.climate
        let system = model.rules.unitSystem
        List {
            Section {
                ForEach(climate.visits) { visit in
                    NavigationLink(value: LogRoute.visit(visit.visitID)) {
                        HStack {
                            PlaceRow(place: visit.place, subtitle: visit.date.displayText)
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Format.temperature(visit.temperatureC, system))
                                    .monospacedDigit()
                                if visit.isAnnualMean {
                                    Text("year's average")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let caveat = climate.temperatureInput.caveat(counting: "visits") {
                        Text(caveat)
                    }
                    Text("""
                    The 1991–2020 average for the place and month, from TerraClimate, \
                    corrected to the place's elevation. A visit across two months weighs \
                    each by its days.
                    """)
                }
            }
        }
        .navigationTitle("Temperatures")
    }
}
