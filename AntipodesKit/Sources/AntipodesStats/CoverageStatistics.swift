import AntipodesCore
import Foundation

/// Where the user has been: the coverage family (§7).
///
/// Counts unique *places*, not visits — the Colosseum twice is one landmark
/// (R-CALC-3). The time-based families count visits instead.
public struct CoverageStatistics: Hashable, Sendable {
    /// Every country visited, whatever list it is on.
    public let countryCodes: Set<String>
    /// The visited countries that are on the list the user counts against (Q-4). This,
    /// not `countryCodes`, is the numerator of "% of the world" — dividing every ISO code
    /// visited by 193 UN members would let Greenland and Hong Kong inflate a share of a
    /// list they are not on.
    public let listedCountryCodes: Set<String>
    public let continents: Set<Continent>
    public let regionCodes: Set<String>
    public let cityIDs: Set<Int64>
    public let landmarkIDs: Set<PlaceID>
    public let airportIDs: Set<PlaceID>
    public let customPinIDs: Set<PlaceID>
    /// National capitals, where the place database says a visited city is one.
    public let capitalCityIDs: Set<Int64>
    /// Landmarks listed by UNESCO in their own right.
    public let unescoLandmarkIDs: Set<PlaceID>

    /// Names for display, keyed by code or id.
    public let countryNames: [String: String]
    public let regionNames: [String: String]
    public let cityNames: [Int64: String]

    /// The visits behind each country, so every number can open the records it rests
    /// on (§7, "every number MUST be tappable").
    public let visitIDsByCountry: [String: [UUID]]
    /// The earliest known day each country was first visited, for "new countries per
    /// year" and for when an achievement was earned.
    public let firstDayByCountry: [String: CalendarDate]

    /// How many countries "% of the world" measures against (Q-4).
    public let worldCountryCount: Int
    public let countryList: CountryList

    public let input: StatInputSummary

    public var countriesVisited: Int {
        countryCodes.count
    }

    /// Countries counted towards "% of the world" under the chosen list.
    public var listedCountriesVisited: Int {
        listedCountryCodes.count
    }

    /// Visited places with their own ISO code that are not on the chosen list —
    /// Greenland or Hong Kong for someone counting UN members.
    public var unlistedCountryCodes: Set<String> {
        countryCodes.subtracting(listedCountryCodes)
    }

    public var continentsVisited: Int {
        continents.count
    }

    public var regionsVisited: Int {
        regionCodes.count
    }

    public var citiesVisited: Int {
        cityIDs.count
    }

    public var landmarksVisited: Int {
        landmarkIDs.count
    }

    public var airportsVisited: Int {
        airportIDs.count
    }

    public var customPinsLogged: Int {
        customPinIDs.count
    }

    public var capitalsVisited: Int {
        capitalCityIDs.count
    }

    public var unescoSitesVisited: Int {
        unescoLandmarkIDs.count
    }

    /// Share of the world's countries visited, in 0...1.
    public var worldFraction: Double {
        min(1, Double(listedCountryCodes.count) / Double(max(1, worldCountryCount)))
    }

    public var continentFraction: Double {
        Double(continents.count) / Double(Continent.allSeven.count)
    }

    public var hasVisitedAllSevenContinents: Bool {
        continents.count == Continent.allSeven.count
    }

    public var countriesSortedByName: [(code: String, name: String)] {
        countryCodes
            .map { (code: $0, name: countryNames[$0] ?? $0) }
            .sorted { ($0.name, $0.code) < ($1.name, $1.code) }
    }

    // One pass over the visits tallies every coverage figure.
    // swiftlint:disable cyclomatic_complexity function_body_length
    /// Computes coverage from a log.
    ///
    /// A visit implies its whole hierarchy chain — a landmark counts its city, region
    /// and country (R-MODEL-6) — and nothing wider than that chain.
    ///
    /// `gazetteer` supplies what the log alone cannot know: which list each country is
    /// on, which cities are capitals and which landmarks are UNESCO-listed. With an
    /// empty one every visited country is treated as listed, which is what a test of
    /// the counting rules wants.
    public static func compute(
        for log: TravelLog,
        rules: CountingRules = .default,
        gazetteer: Gazetteer = .empty
    ) -> CoverageStatistics {
        var countryCodes: Set<String> = []
        var continents: Set<Continent> = []
        var regionCodes: Set<String> = []
        var cityIDs: Set<Int64> = []
        var landmarkIDs: Set<PlaceID> = []
        var airportIDs: Set<PlaceID> = []
        var customPinIDs: Set<PlaceID> = []
        var capitals: Set<Int64> = []
        var unesco: Set<PlaceID> = []
        var countryNames: [String: String] = [:]
        var regionNames: [String: String] = [:]
        var cityNames: [Int64: String] = [:]
        var visitIDsByCountry: [String: [UUID]] = [:]
        var firstDayByCountry: [String: CalendarDate] = [:]
        var input = StatInputSummary()

        for visit in log.visits {
            guard rules.countsTowardsCoverage(visit.visitType) else {
                input.exclude(.visitTypeNotCounted)
                continue
            }
            let place = visit.place
            guard let countryCode = place.countryCode else {
                input.exclude(.missingCountry)
                continue
            }
            input.include()

            countryCodes.insert(countryCode)
            visitIDsByCountry[countryCode, default: []].append(visit.id)
            if let day = visit.date.sortDay, day < (firstDayByCountry[countryCode] ?? day.next) {
                firstDayByCountry[countryCode] = day
            }
            if let name = place.countryName {
                countryNames[countryCode] = name
            }
            if let continent = place.continent ?? gazetteer.country(countryCode)?.continent {
                continents.insert(continent)
            }
            if let region = place.qualifiedRegionCode {
                regionCodes.insert(region)
                if let name = place.regionName {
                    regionNames[region] = name
                }
            }
            if let city = place.impliedCityID {
                cityIDs.insert(city)
                if let name = place.cityName ?? (place.kind == .city ? place.name : nil) {
                    cityNames[city] = name
                }
                if gazetteer.facts(for: .database(.city, city))?.isCapital == true {
                    capitals.insert(city)
                }
            }

            switch place.kind {
            case .landmark:
                landmarkIDs.insert(place.id)
                if gazetteer.facts(for: place.id)?.isUNESCO == true {
                    unesco.insert(place.id)
                }
            case .airport: airportIDs.insert(place.id)
            case .custom: customPinIDs.insert(place.id)
            case .country, .region, .city, .route: break
            }
        }

        let listed: Set<String> =
            if gazetteer.countries.isEmpty {
                countryCodes
            } else {
                countryCodes
                    .filter { gazetteer.country($0)?.isCounted(on: rules.countryList) ?? false }
            }

        return CoverageStatistics(
            countryCodes: countryCodes,
            listedCountryCodes: listed,
            continents: continents,
            regionCodes: regionCodes,
            cityIDs: cityIDs,
            landmarkIDs: landmarkIDs,
            airportIDs: airportIDs,
            customPinIDs: customPinIDs,
            capitalCityIDs: capitals,
            unescoLandmarkIDs: unesco,
            countryNames: countryNames,
            regionNames: regionNames,
            cityNames: cityNames,
            visitIDsByCountry: visitIDsByCountry,
            firstDayByCountry: firstDayByCountry,
            worldCountryCount: rules.worldCountryCount,
            countryList: rules.countryList,
            input: input
        )
    }
    // swiftlint:enable cyclomatic_complexity function_body_length
}

extension CalendarDate {
    /// The following day. Only used as a "later than anything" sentinel inside a
    /// comparison, so it never needs to be valid beyond being greater.
    var next: CalendarDate {
        CalendarDate(year: year + 1, month: 1, day: 1) ?? self
    }
}

/// The furthest points reached, part of the coverage family's "extreme points".
public struct ExtremePoints: Hashable, Sendable {
    public let northernmost: Visit?
    public let southernmost: Visit?
    public let easternmost: Visit?
    public let westernmost: Visit?
    /// The visited place with the greatest and least elevation the database records.
    public let highest: ElevatedVisit?
    public let lowest: ElevatedVisit?
    public let input: StatInputSummary

    /// The point on exactly the other side of the globe from home — the stat the app is
    /// named after.
    public let antipodeOfHome: Coordinate?
    /// The visit closest to that point, and how far it is from it.
    public let nearestToAntipodeOfHome: Visit?
    public let nearestToAntipodeKm: Double?
    /// The visit furthest from home, and how far.
    public let furthestFromHome: Visit?
    public let furthestFromHomeKm: Double?

    public static func compute(
        for log: TravelLog,
        rules: CountingRules = .default,
        home: Coordinate? = nil,
        gazetteer: Gazetteer = .empty
    ) -> ExtremePoints {
        var input = StatInputSummary()
        var located: [(Visit, Coordinate)] = []

        for visit in log.visits {
            guard rules.countsTowardsCoverage(visit.visitType) else {
                input.exclude(.visitTypeNotCounted)
                continue
            }
            guard let coordinate = visit.place.coordinate else {
                input.exclude(.missingCoordinate)
                continue
            }
            input.include()
            located.append((visit, coordinate))
        }

        let antipode = home?.antipode
        let nearest = antipode.flatMap { target in
            located
                .map { ($0.0, GreatCircle.distanceKm(from: $0.1, to: target)) }
                .min { $0.1 < $1.1 }
        }
        let furthest = home.flatMap { home in
            located
                .map { ($0.0, GreatCircle.distanceKm(from: $0.1, to: home)) }
                .max { $0.1 < $1.1 }
        }

        let elevations = located.compactMap { visit, _ -> (Visit, Double)? in
            gazetteer.facts(for: visit.place.id)?.elevationM.map { (visit, $0) }
        }

        return ExtremePoints(
            northernmost: located.max { $0.1.latitude < $1.1.latitude }?.0,
            southernmost: located.min { $0.1.latitude < $1.1.latitude }?.0,
            easternmost: located.max { $0.1.longitude < $1.1.longitude }?.0,
            westernmost: located.min { $0.1.longitude < $1.1.longitude }?.0,
            highest: elevations.max { $0.1 < $1.1 }.map { ElevatedVisit(
                visit: $0.0,
                elevationM: $0.1
            ) },
            lowest: elevations.min { $0.1 < $1.1 }
                .map { ElevatedVisit(visit: $0.0, elevationM: $0.1) },
            input: input,
            antipodeOfHome: antipode,
            nearestToAntipodeOfHome: nearest?.0,
            nearestToAntipodeKm: nearest?.1,
            furthestFromHome: furthest?.0,
            furthestFromHomeKm: furthest?.1
        )
    }
}

/// A visit with the elevation the database records for its place.
public struct ElevatedVisit: Hashable, Sendable {
    public let visit: Visit
    public let elevationM: Double
}
