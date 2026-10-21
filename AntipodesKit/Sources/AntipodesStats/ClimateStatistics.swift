import AntipodesCore
import Foundation

/// One visit and the normal temperature of the time it was made.
public struct VisitTemperature: Hashable, Sendable, Identifiable {
    public var id: UUID {
        visitID
    }

    public let visitID: UUID
    public let place: PlaceReference
    public let date: FlexibleDate
    public let temperatureC: Double
    /// Dated only to the year, so the annual mean stands in for the month (R-DATE-3).
    public let isAnnualMean: Bool
}

/// The weather of where and when the user went: the temperature in the month visited
/// and the climate zones reached (§7, "Place attributes"; R-CALC-2, R-DATE-3).
///
/// Every figure is a 1991-2020 climate normal, not the weather on the day: it says how
/// warm a place usually is in that month. A visit counts once per visit, so a city
/// visited in January and again in July adds both.
public struct ClimateStatistics: Hashable, Sendable {
    public let averageTemperatureC: Double?
    public let hottest: VisitTemperature?
    public let coldest: VisitTemperature?
    /// Every measured visit, warmest first.
    public let visits: [VisitTemperature]
    /// Visits dated only to the year, measured by the annual mean and flagged.
    public let annualMeanCount: Int
    public let temperatureInput: StatInputSummary

    /// Places reached, under each climate zone they sit in. Each place once.
    public let placesByZone: [ClimateZone: [PlaceReference]]
    public let zoneInput: StatInputSummary

    public var zones: [ClimateZone] {
        placesByZone.keys.sorted()
    }

    public var groups: Set<ClimateZone.Group> {
        Set(placesByZone.keys.map(\.group))
    }

    public static func compute(
        for log: TravelLog,
        rules: CountingRules = .default,
        gazetteer: Gazetteer
    ) -> ClimateStatistics {
        var measured: [VisitTemperature] = []
        var annualMeans = 0
        var temperatureInput = StatInputSummary()
        var zonePlaces: [ClimateZone: [PlaceID: PlaceReference]] = [:]
        var zoneInput = StatInputSummary()
        var zonedPlaces: Set<PlaceID> = []

        let counted = log.visits
            .filter { rules.countsTowardsCoverage($0.visitType) }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        for visit in counted {
            let facts = climateFacts(for: visit.place, in: gazetteer)

            // Zones are about places, so each place is counted once.
            if zonedPlaces.insert(visit.place.id).inserted {
                if let code = facts?.koppen, let zone = ClimateZone(code: code) {
                    zoneInput.include()
                    zonePlaces[zone, default: [:]][visit.place.id] = visit.place
                } else {
                    zoneInput.exclude(.attributeUnknown)
                }
            }

            guard let months = facts?.monthlyMeanTemperatureC, months.count == 12 else {
                temperatureInput.exclude(.attributeUnknown)
                continue
            }
            guard let (value, isAnnual) = temperature(on: visit.date, months: months) else {
                temperatureInput.exclude(.unknownDate)
                continue
            }
            temperatureInput.include()
            annualMeans += isAnnual ? 1 : 0
            measured.append(VisitTemperature(
                visitID: visit.id,
                place: visit.place,
                date: visit.date,
                temperatureC: value,
                isAnnualMean: isAnnual
            ))
        }

        let warmestFirst = measured.sorted {
            ($0.temperatureC, $1.place.name) > ($1.temperatureC, $0.place.name)
        }
        // Hottest and coldest are claims about a month, so a year-only visit — which
        // only has the year's mean — cannot be either.
        let monthly = warmestFirst.filter { !$0.isAnnualMean }
        return ClimateStatistics(
            averageTemperatureC: Summary.mean(measured.map(\.temperatureC)),
            hottest: monthly.first,
            coldest: monthly.last,
            visits: warmestFirst,
            annualMeanCount: annualMeans,
            temperatureInput: temperatureInput,
            placesByZone: zonePlaces.mapValues { places in
                places.values.sorted { $0.name < $1.name }
            },
            zoneInput: zoneInput
        )
    }

    /// A place's climate, or its city's: a landmark visited in Rome has Rome's weather
    /// even if the landmark itself had no grid cell to read.
    static func climateFacts(for place: PlaceReference, in gazetteer: Gazetteer) -> PlaceFacts? {
        if let own = gazetteer.facts(for: place.id),
           own.monthlyMeanTemperatureC != nil || own.koppen != nil {
            return own
        }
        if let city = place.cityID {
            return gazetteer.facts(for: .database(.city, city))
        }
        return nil
    }

    /// The normal temperature of a date, and whether it is the annual mean standing in
    /// for an unknown month.
    ///
    /// A day or a month takes that month's normal. A range takes each month's normal
    /// weighted by the days it spent in it, so 28 June to 3 July is three days of June
    /// and three of July. A year takes the annual mean, flagged (R-DATE-3); an unknown
    /// date has no temperature.
    static func temperature(on date: FlexibleDate, months: [Double]) -> (Double, Bool)? {
        switch date {
        case let .day(day):
            return (months[day.month - 1], false)
        case let .month(_, month):
            return (months[month - 1], false)
        case let .range(start, end):
            var total = 0.0
            var days = 0
            var day: CalendarDate? = start
            // Capped at a year: beyond that every month weighs in anyway.
            while let current = day, current <= end, days < 366 {
                total += months[current.month - 1]
                days += 1
                day = current.adding(days: 1)
            }
            return days == 0 ? nil : (total / Double(days), false)
        case .year:
            return (months.reduce(0, +) / 12, true)
        case .unknown:
            return nil
        }
    }
}
