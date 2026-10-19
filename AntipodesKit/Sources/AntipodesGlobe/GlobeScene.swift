import AntipodesCore
import Foundation

/// What the globe is currently showing: the year, trip and mode filters, and where the
/// replay timeline is parked (§9).
public struct GlobeFilter: Hashable, Sendable {
    public var year: Int?
    public var tripID: UUID?
    /// Restricts the arcs drawn. Visits have no mode, so pins are left alone: filtering
    /// to flights should still show where you have been.
    public var mode: TravelMode?
    /// Replay position. Everything dated on or before this day is shown; `nil` shows
    /// the whole log.
    public var replayUpTo: CalendarDate?

    public static let none = GlobeFilter()

    public init(
        year: Int? = nil,
        tripID: UUID? = nil,
        mode: TravelMode? = nil,
        replayUpTo: CalendarDate? = nil
    ) {
        self.year = year
        self.tripID = tripID
        self.mode = mode
        self.replayUpTo = replayUpTo
    }

    public var isFiltering: Bool {
        year != nil || tripID != nil || mode != nil
    }
}

/// How a pin is drawn.
public enum GlobePinStyle: String, Sendable, Hashable, CaseIterable {
    /// A visit that counts towards coverage under the current rules.
    case visited
    /// Logged, but not counted — passed through, or a layover (R-CALC-1). Drawn fainter
    /// so the globe agrees with the coverage number beside it.
    case notCounted
    /// Somewhere the user wants to go, not somewhere they have been (R-GLOBE-4).
    case wishlist
    /// Where the user lives.
    case home
    /// The point on exactly the other side of the globe from home — the app's namesake.
    case antipode

    /// Whether this pin stands for somewhere the user has been. Home, its antipode and
    /// wishlist places are markers, not travel, and are never counted as places.
    public var isTravel: Bool {
        self == .visited || self == .notCounted
    }
}

public struct GlobePin: Identifiable, Sendable {
    public let id: UUID
    public let coordinate: Coordinate
    public let place: PlaceReference
    public let style: GlobePinStyle
    /// `nil` for a wishlist pin, which is not a visit.
    public let visitType: VisitType?
    public let date: FlexibleDate
}

public struct GlobeArc: Identifiable, Sendable {
    public let id: UUID
    public let mode: TravelMode
    public let origin: PlaceReference
    public let destination: PlaceReference
    /// The sampled great circle, straight from `AntipodesCore`. The globe never works
    /// out a path of its own, so the line drawn is the line the distance was measured
    /// along (R-PATH-4, AGENTS.md §7).
    public let path: [Coordinate]
    public let date: FlexibleDate

    public var title: String {
        "\(origin.name) → \(destination.name)"
    }
}

/// Everything the globe draws, worked out once per change rather than per frame.
public struct GlobeScene: Sendable {
    public let pins: [GlobePin]
    public let arcs: [GlobeArc]
    /// ISO 3166-1 alpha-2 codes to shade. Only visits that count towards coverage
    /// contribute, so the shading and the "countries visited" number never disagree
    /// (R-CALC-1).
    public let shadedCountryCodes: Set<String>
    /// Total distance of the arcs actually drawn, in kilometres.
    ///
    /// Summed from each leg's own resolved `distance`, never worked out from
    /// coordinates here — `AntipodesCore.GreatCircle` stays the single implementation
    /// (AGENTS.md §7). It is the scene's own total rather than the whole log's, so the
    /// number beside the globe describes the globe: filter to one trip and it is that
    /// trip's distance.
    public let totalDistanceKm: Double
    /// What could not be drawn, and why. The globe reports this the same way a stat
    /// does: a place quietly missing from the map is the failure this app avoids.
    public let pinSummary: StatInputSummary
    public let arcSummary: StatInputSummary
    public let shadingSummary: StatInputSummary

    public static let empty = GlobeScene(
        pins: [],
        arcs: [],
        shadedCountryCodes: [],
        totalDistanceKm: 0,
        pinSummary: StatInputSummary(),
        arcSummary: StatInputSummary(),
        shadingSummary: StatInputSummary()
    )

    public var isEmpty: Bool {
        pins.isEmpty && arcs.isEmpty && shadedCountryCodes.isEmpty
    }
}

/// Turns the log into drawable content.
///
/// Pure, and tested on its own: everything about what the globe shows is decided here
/// rather than inside a `Canvas` closure (AGENTS.md §4).
public enum GlobeSceneBuilder {
    /// Segments per arc. 48 is smooth at globe scale and cheap enough to rebuild while
    /// the timeline is being scrubbed.
    public static let defaultArcSegments = 48

    public static func build(
        log: TravelLog,
        rules: CountingRules,
        filter: GlobeFilter = .none,
        wishlist: [PlaceReference] = [],
        home: PlaceReference? = nil,
        arcSegments: Int = defaultArcSegments
    ) -> GlobeScene {
        let places = buildPins(log: log, rules: rules, filter: filter, wishlist: wishlist)
        let journeys = buildArcs(log: log, rules: rules, filter: filter, segments: arcSegments)

        // Home and its antipode are drawn as markers, outside the bookkeeping: they are
        // not records, so they are neither drawn nor excluded as travel.
        var pins = places.pins
        if let home, let coordinate = home.coordinate {
            pins.append(GlobePin(
                id: markerID(1),
                coordinate: coordinate,
                place: home,
                style: .home,
                visitType: nil,
                date: .unknown
            ))
            pins.append(GlobePin(
                id: markerID(2),
                coordinate: coordinate.antipode,
                place: PlaceReference(
                    id: .custom(markerID(2)),
                    kind: .custom,
                    name: "Your antipode",
                    coordinate: coordinate.antipode
                ),
                style: .antipode,
                visitType: nil,
                date: .unknown
            ))
        }

        return GlobeScene(
            pins: pins,
            arcs: journeys.arcs,
            shadedCountryCodes: places.shadedCountryCodes,
            totalDistanceKm: journeys.totalDistanceKm,
            pinSummary: places.pinSummary,
            arcSummary: journeys.summary,
            shadingSummary: places.shadingSummary
        )
    }

    /// Fixed identities for the home markers, so a selection survives a rebuild.
    static func markerID(_ index: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, index))
    }

    private struct Places {
        var pins: [GlobePin] = []
        var shadedCountryCodes: Set<String> = []
        var pinSummary = StatInputSummary()
        var shadingSummary = StatInputSummary()
    }

    private struct Journeys {
        var arcs: [GlobeArc] = []
        var totalDistanceKm = 0.0
        var summary = StatInputSummary()
    }

    private static func buildPins(
        log: TravelLog,
        rules: CountingRules,
        filter: GlobeFilter,
        wishlist: [PlaceReference]
    ) -> Places {
        var result = Places()

        for visit in log.visits {
            guard passes(filter, tripID: visit.tripID, date: visit.date) else { continue }

            let counts = rules.countsTowardsCoverage(visit.visitType)

            if filter.replayUpTo != nil, !visit.date.isKnown {
                // Replay orders by date, so an undated visit has nowhere to sit on the
                // timeline. Counted, not dropped silently.
                result.pinSummary.exclude(.unknownDate)
                if counts {
                    result.shadingSummary.exclude(.unknownDate)
                }
                continue
            }

            if let coordinate = visit.place.coordinate {
                result.pinSummary.include()
                result.pins.append(
                    GlobePin(
                        id: visit.id,
                        coordinate: coordinate,
                        place: visit.place,
                        style: counts ? .visited : .notCounted,
                        visitType: visit.visitType,
                        date: visit.date
                    )
                )
            } else {
                result.pinSummary.exclude(.missingCoordinate)
            }

            // Shading is about countries, which a visit can have without a coordinate.
            if counts {
                if let code = visit.place.countryCode {
                    result.shadingSummary.include()
                    result.shadedCountryCodes.insert(code)
                } else {
                    result.shadingSummary.exclude(.missingCountry)
                }
            }
        }

        for place in wishlist {
            guard let coordinate = place.coordinate else {
                result.pinSummary.exclude(.missingCoordinate)
                continue
            }
            result.pinSummary.include()
            result.pins.append(
                GlobePin(
                    id: UUID(),
                    coordinate: coordinate,
                    place: place,
                    style: .wishlist,
                    visitType: nil,
                    date: .unknown
                )
            )
        }

        return result
    }

    private static func buildArcs(
        log: TravelLog,
        rules: CountingRules,
        filter: GlobeFilter,
        segments: Int
    ) -> Journeys {
        var result = Journeys()

        for journey in log.journeys {
            for leg in journey.legs {
                guard passes(filter, tripID: journey.tripID, date: leg.date),
                      filter.mode == nil || leg.mode == filter.mode
                else { continue }

                // Commutes follow the stats setting, so the picture and the distance
                // total cover the same legs (Q-15).
                guard rules.countsInStats(leg.purpose) else {
                    result.summary.exclude(.commuteExcluded)
                    continue
                }
                if filter.replayUpTo != nil, !leg.date.isKnown {
                    result.summary.exclude(.unknownDate)
                    continue
                }

                let path = leg.pathForDisplay(segments: segments)
                guard path.count > 1 else {
                    result.summary.exclude(.missingCoordinate)
                    continue
                }

                result.summary.include()
                if leg.distanceSource != .unavailable {
                    result.totalDistanceKm += leg.distanceKm
                }
                result.arcs.append(
                    GlobeArc(
                        id: leg.id,
                        mode: leg.mode,
                        origin: leg.origin,
                        destination: leg.destination,
                        path: path,
                        date: leg.date
                    )
                )
            }
        }

        return result
    }

    /// The filters that apply to both visits and legs.
    ///
    /// A record the user filtered out is not an exclusion: the bookkeeping is for
    /// records the globe *could not* draw, not ones it was asked not to.
    private static func passes(_ filter: GlobeFilter, tripID: UUID?, date: FlexibleDate) -> Bool {
        if let year = filter.year, date.year != year {
            return false
        }
        if let wanted = filter.tripID, tripID != wanted {
            return false
        }
        // A record with no date is deliberately *not* rejected here. It cannot be placed
        // on the replay timeline, but that is a gap in the data rather than something
        // the user filtered out, so it has to reach the bookkeeping above and be counted
        // (R-DATE-2). Rejecting it here is how it would vanish without trace.
        if let limit = filter.replayUpTo, let day = date.sortDay, day > limit {
            return false
        }
        return true
    }
}

// MARK: - Framing

public extension GlobeScene {
    /// Where to point the camera so that what the scene draws is actually in view.
    ///
    /// The mean of the directions to everything drawn, normalised back onto the sphere.
    /// Averaging latitude and longitude instead would put the midpoint of Tokyo and Los
    /// Angeles in the Sahara, because longitude wraps; averaging direction vectors does
    /// not have that problem.
    ///
    /// `nil` when there is nothing to look at, or when what there is averages out to
    /// the centre of the Earth — travel spread evenly over the whole globe has no one
    /// side to show.
    var focusCoordinate: Coordinate? {
        var sum = Vector3(x: 0, y: 0, z: 0)
        var count = 0

        // Home and its antipode would cancel each other out, and are not travel.
        for pin in pins where pin.style.isTravel || pin.style == .wishlist {
            sum = sum.adding(Vector3.onUnitSphere(pin.coordinate))
            count += 1
        }
        for arc in arcs {
            guard let origin = arc.path.first, let destination = arc.path.last else { continue }
            sum = sum.adding(Vector3.onUnitSphere(origin))
            sum = sum.adding(Vector3.onUnitSphere(destination))
            count += 2
        }

        guard count > 0 else { return nil }
        let length = (sum.x * sum.x + sum.y * sum.y + sum.z * sum.z).squareRoot()
        guard length > 1e-6 else { return nil }
        return sum.coordinate
    }
}

// MARK: - Hit testing

/// What a tap on the globe landed on (§9).
public enum GlobeSelection: Sendable, Identifiable {
    case pin(GlobePin)
    case arc(GlobeArc)

    /// The underlying visit or leg, which is also what a detail view is keyed on.
    public var id: UUID {
        switch self {
        case let .pin(pin): pin.id
        case let .arc(arc): arc.id
        }
    }
}

public extension GlobeScene {
    /// The nearest pin or arc to a point in the view, within `tolerance` points.
    ///
    /// Pins win ties: a pin sitting on top of an arc is the more specific thing to open.
    /// Hidden geometry on the far side of the globe is never selected.
    func selection(
        at point: GlobePoint,
        globe: OrthographicGlobe,
        tolerance: Double = 22
    ) -> GlobeSelection? {
        var bestPin: (pin: GlobePin, distance: Double)?
        for pin in pins {
            let projected = globe.project(pin.coordinate)
            guard projected.isVisible else { continue }
            let distance = projected.point.distance(to: point)
            guard distance <= tolerance else { continue }
            if bestPin == nil || distance < bestPin!.distance {
                bestPin = (pin, distance)
            }
        }
        if let bestPin {
            return .pin(bestPin.pin)
        }

        var bestArc: (arc: GlobeArc, distance: Double)?
        for arc in arcs {
            for run in globe.clippedPolyline(arc.path) {
                for (start, end) in zip(run, run.dropFirst()) {
                    let distance = distanceFromPoint(point, toSegmentFrom: start, to: end)
                    guard distance <= tolerance else { continue }
                    if bestArc == nil || distance < bestArc!.distance {
                        bestArc = (arc, distance)
                    }
                }
            }
        }
        return bestArc.map { .arc($0.arc) }
    }
}

/// Shortest distance from a point to a line segment.
func distanceFromPoint(
    _ point: GlobePoint,
    toSegmentFrom start: GlobePoint,
    to end: GlobePoint
) -> Double {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let squaredLength = dx * dx + dy * dy
    guard squaredLength > 0 else { return point.distance(to: start) }

    let t = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / squaredLength))
    return point.distance(to: GlobePoint(x: start.x + t * dx, y: start.y + t * dy))
}
