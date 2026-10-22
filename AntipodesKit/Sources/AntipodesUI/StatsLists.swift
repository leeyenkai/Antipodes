import AntipodesCore
import AntipodesStats
import SwiftUI

struct RepeatVisitsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(model.shownStatistics.time.repeatVisits, id: \.place.id) { repeated in
            NavigationLink(value: StatsRoute.visits(
                title: repeated.place.name,
                ids: model.shownLog.visits
                    .filter { $0.place.id == repeated.place.id }
                    .filter { model.shownRules.countsTowardsCoverage($0.visitType) }
                    .map(\.id)
            )) {
                HStack {
                    PlaceRow(place: repeated.place)
                    Spacer()
                    Text("\(repeated.visitCount)×")
                        .font(.headline.monospacedDigit())
                }
            }
        }
        .navigationTitle("Places returned to")
    }
}

struct CountryGapsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(model.shownStatistics.time.countryGaps, id: \.countryCode) { gap in
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

/// Any set of visits, newest first, each opening itself.
struct VisitListView: View {
    @Environment(AppModel.self) private var model
    let title: String
    let ids: [UUID]

    var body: some View {
        let wanted = Set(ids)
        let visits = model.shownLog.visits.filter { wanted.contains($0.id) }
            .sorted { $0.date > $1.date }
        List {
            ForEach(visits) { visit in
                NavigationLink(value: LogRoute.visit(visit.id)) {
                    VisitRow(visit: visit)
                }
            }
            if visits.isEmpty {
                ContentUnavailableView("No visits", systemImage: "mappin.slash")
            }
        }
        .navigationTitle(title)
    }
}

/// The continents reached, each with the countries in it.
struct ContinentListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let coverage = model.shownStatistics.coverage
        let byContinent = Dictionary(grouping: coverage.countriesSortedByName) { country in
            model.catalogue.countries[country.code]?.continent
        }
        List {
            ForEach(Continent.allSeven, id: \.self) { continent in
                let countries = byContinent[continent] ?? []
                Section {
                    if countries.isEmpty {
                        Text("Not yet").foregroundStyle(.secondary)
                    }
                    ForEach(countries, id: \.code) { country in
                        NavigationLink(value: LogRoute.country(country.code)) {
                            Label {
                                Text(country.name)
                            } icon: {
                                Text(Format.flag(country.code))
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(continent.displayName)
                        Spacer()
                        Text(Format.ordinalCount(countries.count, "country", "countries"))
                    }
                }
            }
        }
        .navigationTitle("Continents")
    }
}

/// Every trip, newest first, with how long it was — what "trips" and "days away" rest on.
struct TripStatsList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // The trips in the slice the Stats screen shows, so the list and its "No trips
        // yet" never disagree.
        let shown = Set(model.shownLog.trips.map(\.id))
        List {
            ForEach(model.tripsNewestFirst.filter { shown.contains($0.id) }) { trip in
                NavigationLink(value: LogRoute.trip(trip.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trip.displayName(model: model))
                        if let dates = model.dates(ofTrip: trip.id) {
                            Text(dates.textWithLength)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if model.shownLog.trips.isEmpty {
                ContentUnavailableView("No trips yet", systemImage: "suitcase")
            }
        }
        .navigationTitle("Trips")
    }
}
