import AntipodesCore
import Foundation

/// Where the user has been: the coverage family (§7).
///
/// Counts unique *places*, not visits — the Colosseum twice is one landmark
/// (R-CALC-3). The time-based families count visits instead.
public struct CoverageStatistics: Hashable, Sendable {
    public let countryCodes: Set<String>
    public let continents: Set<Continent>
    public let regionCodes: Set<String>
    public let cityIDs: Set<Int64>
    public let landmarkIDs: Set<PlaceID>
    public let airportIDs: Set<PlaceID>
    public let customPinIDs: Set<PlaceID>

    /// Country names for display, keyed by ISO code.
    public let countryNames: [String: String]

    /// How many countries "% of the world" measures against (Q-4).
    public let worldCountryCount: Int

    public let input: StatInputSummary

    public var countriesVisited: Int {
        countryCodes.count
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

    /// Share of the world's countries visited, in 0...1.
    public var worldFraction: Double {
        min(1, Double(countryCodes.count) / Double(max(1, worldCountryCount)))
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

    /// Computes coverage from a log.
    ///
    /// A visit implies its whole hierarchy chain — a landmark counts its city, region
    /// and country (R-MODEL-6) — and nothing wider than that chain.
    public static func compute(
        for log: TravelLog,
        rules: CountingRules = .default
    ) -> CoverageStatistics {
        var countryCodes: Set<String> = []
        var continents: Set<Continent> = []
        var regionCodes: Set<String> = []
        var cityIDs: Set<Int64> = []
        var landmarkIDs: Set<PlaceID> = []
        var airportIDs: Set<PlaceID> = []
        var customPinIDs: Set<PlaceID> = []
        var countryNames: [String: String] = [:]
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
            if let name = place.countryName {
                countryNames[countryCode] = name
            }
            if let continent = place.continent {
                continents.insert(continent)
            }
            if let region = place.qualifiedRegionCode {
                regionCodes.insert(region)
            }
            if let city = place.impliedCityID {
                cityIDs.insert(city)
            }

            switch place.kind {
            case .landmark: landmarkIDs.insert(place.id)
            case .airport: airportIDs.insert(place.id)
            case .custom: customPinIDs.insert(place.id)
            case .country, .region, .city, .route: break
            }
        }

        return CoverageStatistics(
            countryCodes: countryCodes,
            continents: continents,
            regionCodes: regionCodes,
            cityIDs: cityIDs,
            landmarkIDs: landmarkIDs,
            airportIDs: airportIDs,
            customPinIDs: customPinIDs,
            countryNames: countryNames,
            worldCountryCount: rules.worldCountryCount,
            input: input
        )
    }
}

/// The furthest points reached, part of the coverage family's "extreme points".
public struct ExtremePoints: Hashable, Sendable {
    public let northernmost: Visit?
    public let southernmost: Visit?
    public let easternmost: Visit?
    public let westernmost: Visit?
    public let input: StatInputSummary

    /// The visit closest to the antipode of a given point — the stat the app is named
    /// after.
    public let nearestToAntipodeOfHome: Visit?

    public static func compute(
        for log: TravelLog,
        rules: CountingRules = .default,
        home: Coordinate? = nil
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

        let antipodeTarget = home?.antipode
        let nearest = antipodeTarget.flatMap { target in
            located.min { GreatCircle.distanceKm(from: $0.1, to: target)
                < GreatCircle.distanceKm(from: $1.1, to: target)
            }?.0
        }

        return ExtremePoints(
            northernmost: located.max { $0.1.latitude < $1.1.latitude }?.0,
            southernmost: located.min { $0.1.latitude < $1.1.latitude }?.0,
            easternmost: located.max { $0.1.longitude < $1.1.longitude }?.0,
            westernmost: located.min { $0.1.longitude < $1.1.longitude }?.0,
            input: input,
            nearestToAntipodeOfHome: nearest
        )
    }
}
