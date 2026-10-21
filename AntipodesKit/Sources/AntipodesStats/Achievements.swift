import AntipodesCore
import Foundation

/// Where an achievement stands for this log (R-ACH-1 to R-ACH-3).
public struct AchievementStatus: Hashable, Sendable, Identifiable {
    /// What `current` and `target` measure, so the screen can word the progress.
    public enum Measure: String, Hashable, Sendable {
        case count
        case kilometres
        /// How far the closest pair of places is from being exactly antipodal; lower is
        /// better, and the achievement is earned at or below the target.
        case antipodalGapKilometres
        case yesNo
    }

    public var id: String {
        definition.id
    }

    public let definition: AchievementDefinition
    public let measure: Measure
    public let current: Double
    public let target: Double
    public let isEarned: Bool
    /// The day the threshold was crossed, where every record that got it there is
    /// dated to the day. A visit dated only "2019" cannot say which day of 2019.
    public let earnedOn: CalendarDate?

    /// Progress in 0...1, for a ring.
    public var progress: Double {
        if isEarned {
            return 1
        }
        switch measure {
        case .antipodalGapKilometres:
            // 0 when the closest pair is a full half-globe from antipodal, 1 at target.
            guard current.isFinite else { return 0 }
            let worst = GreatCircle.earthCircumferenceKm / 2
            return max(0, min(1, (worst - current) / max(1, worst - target)))
        case .count, .kilometres, .yesNo:
            return target <= 0 ? 0 : max(0, min(1, current / target))
        }
    }
}

/// Evaluates achievement definitions from the database against the log.
///
/// Pure, like every stat: the definitions come in as values (R-ACH-1), and the same rule
/// that decides coverage decides an achievement, so "Ten countries" and the countries
/// number can never disagree.
public enum AchievementEngine {
    public static func evaluate(
        _ definitions: [AchievementDefinition],
        log: TravelLog,
        rules: CountingRules = .default,
        gazetteer: Gazetteer = .empty,
        collections: [CollectionProgress] = []
    ) -> [AchievementStatus] {
        let context = Context(
            log: log,
            rules: rules,
            gazetteer: gazetteer,
            collections: collections
        )
        return definitions
            .sorted { ($0.sortOrder, $0.id) < ($1.sortOrder, $1.id) }
            .compactMap { definition in
                guard let rule = definition.rule else { return nil }
                return context.status(for: definition, rule: rule)
            }
    }

    /// A dated event that adds one distinct key to a running count.
    struct Event: Sendable {
        let day: CalendarDate?
        let key: String
    }

    /// The count of distinct keys, and the first day that count reached `target` —
    /// `nil` if it never did, or only did once undated events were included.
    static func progress(
        of events: [Event],
        target: Int
    ) -> (count: Int, reachedOn: CalendarDate?) {
        let count = Set(events.map(\.key)).count
        guard target > 0, count >= target else { return (count, nil) }
        var seen: Set<String> = []
        for event in events.filter({ $0.day != nil }).sorted(by: { $0.day! < $1.day! }) {
            seen.insert(event.key)
            if seen.count >= target {
                return (count, event.day)
            }
        }
        return (count, nil)
    }

    private struct Context {
        let log: TravelLog
        let rules: CountingRules
        let gazetteer: Gazetteer
        let collections: [String: CollectionProgress]
        let counted: [Visit]
        let statsLegs: [JourneyLeg]

        init(
            log: TravelLog,
            rules: CountingRules,
            gazetteer: Gazetteer,
            collections: [CollectionProgress]
        ) {
            self.log = log
            self.rules = rules
            self.gazetteer = gazetteer
            self.collections = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0) })
            counted = log.visits.filter { rules.countsTowardsCoverage($0.visitType) }
            statsLegs = log.allLegs.filter { rules.countsInStats($0.purpose) }
        }

        // One case per rule; the switch is the rule table.
        // swiftlint:disable cyclomatic_complexity function_body_length
        func status(
            for definition: AchievementDefinition,
            rule: AchievementRule
        ) -> AchievementStatus {
            let target = definition.threshold ?? 1
            switch rule {
            case .countries:
                let listed = { (code: String) -> Bool in
                    gazetteer.countries.isEmpty
                        || (gazetteer.country(code)?.isCounted(on: rules.countryList) ?? false)
                }
                return counting(definition, target, events: counted.compactMap { visit in
                    visit.place.countryCode.flatMap { listed($0) ? Event(
                        day: visit.date.exactStartDay,
                        key: $0
                    ) : nil }
                })
            case .continents:
                return counting(definition, target, events: counted.compactMap { visit in
                    let continent = visit.place.continent ?? gazetteer
                        .country(visit.place.countryCode)?.continent
                    return continent.map { Event(day: visit.date.exactStartDay, key: $0.rawValue) }
                })
            case .regions:
                return counting(definition, target, events: counted.compactMap { visit in
                    visit.place.qualifiedRegionCode.map { Event(
                        day: visit.date.exactStartDay,
                        key: $0
                    ) }
                })
            case .cities:
                return counting(definition, target, events: counted.compactMap { visit in
                    visit.place.impliedCityID
                        .map { Event(day: visit.date.exactStartDay, key: String($0)) }
                })
            case .capitals:
                return counting(definition, target, events: counted.compactMap { visit in
                    guard let city = visit.place.impliedCityID,
                          gazetteer.facts(for: .database(.city, city))?.isCapital == true
                    else { return nil }
                    return Event(day: visit.date.exactStartDay, key: String(city))
                })
            case .landmarks:
                return counting(definition, target, events: counted.compactMap { visit in
                    visit.place.kind == .landmark
                        ? Event(day: visit.date.exactStartDay, key: visit.place.id.description) :
                        nil
                })
            case .unesco:
                return counting(definition, target, events: counted.compactMap { visit in
                    gazetteer.facts(for: visit.place.id)?.isUNESCO == true
                        ? Event(day: visit.date.exactStartDay, key: visit.place.id.description) :
                        nil
                })
            case .airports:
                let fromVisits = counted.compactMap { visit in
                    visit.place.kind == .airport
                        ? Event(day: visit.date.exactStartDay, key: visit.place.id.description) :
                        nil
                }
                let fromLegs = statsLegs.filter { $0.mode == .flight }.flatMap { leg in
                    [leg.origin, leg.destination]
                        .filter { $0.kind == .airport }
                        .map { Event(day: leg.date.exactStartDay, key: $0.id.description) }
                }
                return counting(definition, target, events: fromVisits + fromLegs)
            case .flights:
                return counting(
                    definition,
                    target,
                    events: statsLegs.filter { $0.mode == .flight }.map {
                        Event(day: $0.date.exactStartDay, key: $0.id.uuidString)
                    }
                )
            case .trips:
                // A trip with nothing in it yet is a folder, not a trip taken.
                return counting(definition, target, events: log.trips.compactMap { trip in
                    let visits = log.visits(inTrip: trip.id)
                    let journeys = log.journeys(inTrip: trip.id)
                    guard !visits.isEmpty || !journeys.isEmpty else { return nil }
                    let days = visits.compactMap(\.date.exactStartDay)
                        + journeys.compactMap(\.date.exactStartDay)
                    return Event(day: days.min(), key: trip.id.uuidString)
                })
            case .modes:
                return counting(definition, target, events: statsLegs.map {
                    Event(day: $0.date.exactStartDay, key: $0.mode.rawValue)
                })
            case .distance:
                return distance(definition, target)
            case .collectionComplete, .collectionCount:
                return collection(definition, rule: rule)
            case .unescoInOneTrip:
                return unescoInOneTrip(definition, target)
            case .overnightTrain:
                return counting(
                    definition,
                    target,
                    events: statsLegs.filter { $0.mode == .rail && $0.isOvernight }.map {
                        Event(day: $0.date.exactStartDay, key: $0.id.uuidString)
                    }
                )
            case .crossedEquator, .arcticCircle, .antarcticCircle:
                return latitude(definition, rule: rule)
            case .antipodes:
                return antipodes(definition, target)
            }
        }

        // swiftlint:enable cyclomatic_complexity function_body_length

        private func counting(
            _ definition: AchievementDefinition,
            _ target: Double,
            events: [Event]
        ) -> AchievementStatus {
            let needed = Int(target.rounded(.up))
            let result = AchievementEngine.progress(of: events, target: needed)
            return AchievementStatus(
                definition: definition,
                measure: .count,
                current: Double(result.count),
                target: Double(needed),
                isEarned: result.count >= needed,
                earnedOn: result.reachedOn
            )
        }

        private func distance(
            _ definition: AchievementDefinition,
            _ target: Double
        ) -> AchievementStatus {
            let legs = statsLegs.filter { $0.distanceSource != .unavailable }
            let total = legs.reduce(0) { $0 + $1.distanceKm }
            var earnedOn: CalendarDate?
            if total >= target {
                var running = 0.0
                for leg in legs.filter({ $0.date.exactStartDay != nil })
                    .sorted(by: { $0.date < $1.date }) {
                    running += leg.distanceKm
                    if running >= target {
                        earnedOn = leg.date.exactStartDay
                        break
                    }
                }
            }
            return AchievementStatus(
                definition: definition,
                measure: .kilometres,
                current: total,
                target: target,
                isEarned: total >= target,
                earnedOn: earnedOn
            )
        }

        private func collection(
            _ definition: AchievementDefinition,
            rule: AchievementRule
        ) -> AchievementStatus {
            guard let progress = definition.parameter.flatMap({ collections[$0] }) else {
                return AchievementStatus(
                    definition: definition,
                    measure: .count,
                    current: 0,
                    target: definition.threshold ?? 1,
                    isEarned: false,
                    earnedOn: nil
                )
            }
            let target = rule == .collectionComplete
                ? Double(progress.total)
                : (definition.threshold ?? Double(progress.total))
            let days = progress.members.filter(\.isVisited).map(\.firstVisited)
            var earnedOn: CalendarDate?
            let needed = Int(target.rounded(.up))
            if progress.visitedCount >= needed, needed > 0 {
                let dated = days.compactMap(\.self).sorted()
                if dated.count >= needed {
                    earnedOn = dated[needed - 1]
                }
            }
            return AchievementStatus(
                definition: definition,
                measure: .count,
                current: Double(progress.visitedCount),
                target: target,
                isEarned: progress.visitedCount >= needed && needed > 0,
                earnedOn: earnedOn
            )
        }

        /// Earned on the day the first trip to reach the target reached it: the day of
        /// its target-th site, counting each site from its first day-precise visit.
        private func unescoInOneTrip(
            _ definition: AchievementDefinition,
            _ target: Double
        ) -> AchievementStatus {
            var best = 0
            var earnedOn: CalendarDate?
            let needed = max(1, Int(target.rounded(.up)))
            for trip in log.trips {
                let visits = counted.filter { visit in
                    visit.tripID == trip.id && gazetteer.facts(for: visit.place.id)?
                        .isUNESCO == true
                }
                best = max(best, Set(visits.map(\.place.id)).count)
                var firstDay: [PlaceID: CalendarDate] = [:]
                for visit in visits {
                    guard let day = visit.date.exactStartDay else { continue }
                    firstDay[visit.place.id] = min(firstDay[visit.place.id] ?? day, day)
                }
                let days = firstDay.values.sorted()
                if days.count >= needed {
                    earnedOn = min(earnedOn ?? days[needed - 1], days[needed - 1])
                }
            }
            let isEarned = Double(best) >= target
            return AchievementStatus(
                definition: definition,
                measure: .count,
                current: Double(best),
                target: target,
                isEarned: isEarned,
                earnedOn: isEarned ? earnedOn : nil
            )
        }

        /// Every point the user has demonstrably been at: counted visits, the ends of
        /// legs, and the whole arc of every flight, with the day each happened.
        ///
        /// A flight's great circle is the path it flew (R-PATH-4), so a polar flight that
        /// never lands north of 66.56° still crosses the Arctic Circle. A surface leg's
        /// line is only an approximation of its path, so only its ends count.
        private var points: [(Coordinate, CalendarDate?)] {
            counted
                .compactMap { visit in
                    visit.place.coordinate.map { ($0, visit.date.exactStartDay) }
                }
                + statsLegs.flatMap { leg -> [(Coordinate, CalendarDate?)] in
                    guard let origin = leg.origin.coordinate,
                          let destination = leg.destination.coordinate
                    else {
                        return [leg.origin.coordinate, leg.destination.coordinate]
                            .compactMap(\.self)
                            .map { ($0, leg.date.exactStartDay) }
                    }
                    let path = leg.mode == .flight
                        ? GreatCircle.arc(from: origin, to: destination, segments: 90)
                        : [origin, destination]
                    return path.map { ($0, leg.date.exactStartDay) }
                }
        }

        private func latitude(
            _ definition: AchievementDefinition,
            rule: AchievementRule
        ) -> AchievementStatus {
            let points = points
            let earned: Bool
            var earnedOn: CalendarDate?
            switch rule {
            case .crossedEquator:
                let north = points.filter { $0.0.latitude > 0 }
                let south = points.filter { $0.0.latitude < 0 }
                earned = !north.isEmpty && !south.isEmpty
                if earned, let firstNorth = north.compactMap(\.1).min(),
                   let firstSouth = south.compactMap(\.1).min() {
                    earnedOn = max(firstNorth, firstSouth)
                }
            case .arcticCircle:
                let beyond = points.filter(\.0.isNorthOfArcticCircle)
                earned = !beyond.isEmpty
                earnedOn = beyond.compactMap(\.1).min()
            default:
                let beyond = points.filter(\.0.isSouthOfAntarcticCircle)
                earned = !beyond.isEmpty
                earnedOn = beyond.compactMap(\.1).min()
            }
            return AchievementStatus(
                definition: definition,
                measure: .yesNo,
                current: earned ? 1 : 0,
                target: 1,
                isEarned: earned,
                earnedOn: earned ? earnedOn : nil
            )
        }

        /// The closest any two places the user has been come to being exactly opposite
        /// each other. Coordinates are rounded to a tenth of a degree first, which moves
        /// the answer by no more than ~11 km.
        ///
        /// Two places are closest to antipodal when the angle between them is largest,
        /// which is when the dot product of their unit vectors is smallest. So the pair
        /// is found with three multiplications per pair rather than a haversine, and
        /// only that one pair's distance is measured — by `GreatCircle`, like every
        /// other distance (AGENTS.md §7).
        private func antipodes(
            _ definition: AchievementDefinition,
            _ target: Double
        ) -> AchievementStatus {
            var unique: [String: Coordinate] = [:]
            for (coordinate, _) in points {
                let latitude = (coordinate.latitude * 10).rounded()
                let key = "\(latitude),\((coordinate.longitude * 10).rounded())"
                unique[key] = coordinate
            }
            let coordinates = unique.keys.sorted().compactMap { unique[$0] }
            let vectors = coordinates.map(\.unitVector)
            var bestPair: (Int, Int)?
            var lowestDot = Double.infinity
            for first in vectors.indices {
                let a = vectors[first]
                for second in vectors.indices where second > first {
                    let b = vectors[second]
                    let dot = a.x * b.x + a.y * b.y + a.z * b.z
                    if dot < lowestDot {
                        lowestDot = dot
                        bestPair = (first, second)
                    }
                }
            }
            let best = bestPair.map { first, second in
                GreatCircle.distanceKm(from: coordinates[first].antipode, to: coordinates[second])
            } ?? .infinity
            return AchievementStatus(
                definition: definition,
                measure: .antipodalGapKilometres,
                current: best,
                target: target,
                isEarned: best <= target,
                earnedOn: nil
            )
        }
    }
}
