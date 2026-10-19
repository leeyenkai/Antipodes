import AntipodesCore
import Foundation

/// A place and the value an attribute stat measured for it.
public struct MeasuredPlace: Hashable, Sendable {
    public let place: PlaceReference
    public let value: Double
}

/// What the places themselves are like: the place-attributes family (§7).
///
/// Averages here are over unique *places* — the Colosseum visited twice weighs once in
/// the average landmark age (R-CALC-3). Every figure says how many places it had a
/// value for, because the database leaves unknowns empty (R-DB-2): "average landmark
/// age, based on 42 of 50 landmarks".
///
/// Temperature in the month visited (R-CALC-2) is not here: it needs a climate-normals
/// source that has not been licence-reviewed yet (R-DB-7), and a stat built on a guess
/// would be worse than none.
public struct PlaceAttributeStatistics: Hashable, Sendable {
    /// The year ages are measured to.
    public let referenceYear: Int

    public let averageLandmarkAgeYears: Double?
    public let medianLandmarkAgeYears: Double?
    /// Oldest and newest by year built. A negative value is BC.
    public let oldestLandmark: MeasuredPlace?
    public let newestLandmark: MeasuredPlace?
    public let landmarkAgeInput: StatInputSummary

    public let averageElevationM: Double?
    public let highestPlace: MeasuredPlace?
    public let lowestPlace: MeasuredPlace?
    public let elevationInput: StatInputSummary

    public let averageCityPopulation: Double?
    public let medianCityPopulation: Double?
    public let largestCity: MeasuredPlace?
    public let smallestCity: MeasuredPlace?
    public let cityPopulationInput: StatInputSummary

    /// IANA zones among the places visited.
    public let timeZones: Set<String>
    public let timeZoneInput: StatInputSummary

    /// Main languages and currencies of the countries visited, from the place
    /// database's country facts.
    public let languageCodes: Set<String>
    public let currencyCodes: Set<String>
    public let countryFactsInput: StatInputSummary

    // Gathers the places once, then measures each attribute.
    // swiftlint:disable function_body_length
    public static func compute(
        for log: TravelLog,
        rules: CountingRules = .default,
        gazetteer: Gazetteer,
        referenceYear: Int
    ) -> PlaceAttributeStatistics {
        // Unique places from the visits that count, each once (R-CALC-3).
        var places: [PlaceID: PlaceReference] = [:]
        var cities: [Int64: PlaceReference] = [:]
        var countries: Set<String> = []
        for visit in log.visits where rules.countsTowardsCoverage(visit.visitType) {
            places[visit.place.id] = visit.place
            if let code = visit.place.countryCode {
                countries.insert(code)
            }
            if visit.place.kind == .city, case let .database(.city, row) = visit.place.id {
                cities[row] = visit.place
            } else if let city = visit.place.cityID, cities[city] == nil {
                // A landmark implies its city (R-MODEL-6); the city's population is a
                // fact about the city, so it is measured once under the city's id.
                cities[city] = PlaceReference(
                    id: .database(.city, city),
                    kind: .city,
                    name: visit.place.cityName ?? visit.place.name,
                    countryCode: visit.place.countryCode,
                    countryName: visit.place.countryName,
                    continent: visit.place.continent
                )
            }
        }
        let ordered = places.values.sorted { $0.id.description < $1.id.description }

        // Landmark age, elevation (over every kind the database records one for) and
        // city population.
        let (built, ageInput) = measure(ordered.filter { $0.kind == .landmark }) {
            gazetteer.facts(for: $0.id)?.yearBuilt.map { Double($0) }
        }
        let ages = built.map { Double(referenceYear) - $0.value }
        let (elevations, elevationInput) = measure(
            ordered.filter { $0.kind == .city || $0.kind == .airport }
        ) {
            gazetteer.facts(for: $0.id)?.elevationM
        }
        let (
            populations,
            populationInput
        ) = measure(cities.sorted { $0.key < $1.key }.map(\.value)) {
            gazetteer.facts(for: $0.id)?.population.flatMap { $0 > 0 ? Double($0) : nil }
        }

        // Time zones.
        var zoneInput = StatInputSummary()
        var zones: Set<String> = []
        for place in ordered where place.kind != .country && place.kind != .route {
            if let zone = place.timeZoneIdentifier ?? gazetteer.facts(for: place.id)?
                .timeZoneIdentifier {
                zoneInput.include()
                zones.insert(zone)
            } else {
                zoneInput.exclude(.attributeUnknown)
            }
        }

        // Languages and currencies, per country.
        var countryInput = StatInputSummary()
        var languages: Set<String> = []
        var currencies: Set<String> = []
        for code in countries.sorted() {
            guard let facts = gazetteer.country(code) else {
                countryInput.exclude(.attributeUnknown)
                continue
            }
            countryInput.include()
            if let language = facts.primaryLanguage {
                languages.insert(language)
            }
            if let currency = facts.currencyCode {
                currencies.insert(currency)
            }
        }

        return PlaceAttributeStatistics(
            referenceYear: referenceYear,
            averageLandmarkAgeYears: Summary.mean(ages),
            medianLandmarkAgeYears: Summary.median(ages),
            oldestLandmark: built.min { ($0.value, $0.place.name) < ($1.value, $1.place.name) },
            newestLandmark: built.max { ($0.value, $1.place.name) < ($1.value, $0.place.name) },
            landmarkAgeInput: ageInput,
            averageElevationM: Summary.mean(elevations.map(\.value)),
            highestPlace: elevations.max { $0.value < $1.value },
            lowestPlace: elevations.min { $0.value < $1.value },
            elevationInput: elevationInput,
            averageCityPopulation: Summary.mean(populations.map(\.value)),
            medianCityPopulation: Summary.median(populations.map(\.value)),
            largestCity: populations.max { $0.value < $1.value },
            smallestCity: populations.min { $0.value < $1.value },
            cityPopulationInput: populationInput,
            timeZones: zones,
            timeZoneInput: zoneInput,
            languageCodes: languages,
            currencyCodes: currencies,
            countryFactsInput: countryInput
        )
    }

    // swiftlint:enable function_body_length

    /// Measures each place that has a value, and counts the rest as unknown.
    private static func measure(
        _ places: [PlaceReference],
        _ value: (PlaceReference) -> Double?
    ) -> (measured: [MeasuredPlace], input: StatInputSummary) {
        var input = StatInputSummary()
        var measured: [MeasuredPlace] = []
        for place in places {
            if let found = value(place) {
                input.include()
                measured.append(MeasuredPlace(place: place, value: found))
            } else {
                input.exclude(.attributeUnknown)
            }
        }
        return (measured, input)
    }
}

/// Small summary statistics, written once.
enum Summary {
    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// The middle value, or the mean of the middle two.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
