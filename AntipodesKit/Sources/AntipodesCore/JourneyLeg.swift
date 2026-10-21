import Foundation

/// One stage of a journey: a single vehicle from one place to another (§5.2).
///
/// Only `mode`, `origin` and `destination` are required (R-LEG-1).
public struct JourneyLeg: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var mode: TravelMode
    public var origin: PlaceReference
    public var destination: PlaceReference
    public var date: FlexibleDate
    public var purpose: TripPurpose
    /// Length of the real path, where the pipeline or on-device snapping produced one,
    /// or the catalogue route's length when the whole route was ridden.
    public var storedPathLengthKm: Double?
    /// The user's own figure, which beats any computed one.
    public var distanceKmOverride: Double?
    public var durationMinutesOverride: Int?
    /// Scheduled and actual times, local to each end (§5.2).
    public var times: LegTimes
    /// The connection *into* this leg was missed (R-JLOG-4).
    public var missedConnection: Bool
    /// The catalogue route this leg rode, if any (R-JLOG-3).
    public var routeID: Int64?
    public var routeName: String?
    /// The transit line ridden, from a transit pack (R-JLOG-5); the ends are then its
    /// stops, so the stops passed through can be worked out (R-TRAN-3).
    public var transitLineID: Int64?
    /// The network the ride was logged against, kept so a later network does not
    /// rewrite it (R-TRAN-4): a transit pack, or for a surface leg with no line, the
    /// map of railways, roads or ferry routes its length was measured on (D-30).
    public var networkVersion: String?
    public var operatorName: String?
    public var serviceNumber: String?
    public var vehicle: String?
    /// Aircraft registration, ship name or unit number.
    public var registration: String?
    public var travelClass: String?
    public var seat: String?
    public var rating: Int?
    public var notes: String?

    public init(
        id: UUID = UUID(),
        mode: TravelMode,
        origin: PlaceReference,
        destination: PlaceReference,
        date: FlexibleDate = .unknown,
        purpose: TripPurpose = .leisure,
        storedPathLengthKm: Double? = nil,
        distanceKmOverride: Double? = nil,
        durationMinutesOverride: Int? = nil,
        times: LegTimes = .none,
        missedConnection: Bool = false,
        routeID: Int64? = nil,
        routeName: String? = nil,
        transitLineID: Int64? = nil,
        networkVersion: String? = nil,
        operatorName: String? = nil,
        serviceNumber: String? = nil,
        vehicle: String? = nil,
        registration: String? = nil,
        travelClass: String? = nil,
        seat: String? = nil,
        rating: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.mode = mode
        self.origin = origin
        self.destination = destination
        self.date = date
        self.purpose = purpose
        self.storedPathLengthKm = storedPathLengthKm
        self.distanceKmOverride = distanceKmOverride
        self.durationMinutesOverride = durationMinutesOverride
        self.times = times
        self.missedConnection = missedConnection
        self.routeID = routeID
        self.routeName = routeName
        self.transitLineID = transitLineID
        self.networkVersion = networkVersion
        self.operatorName = operatorName
        self.serviceNumber = serviceNumber
        self.vehicle = vehicle
        self.registration = registration
        self.travelClass = travelClass
        self.seat = seat
        self.rating = rating.map { min(5, max(1, $0)) }
        self.notes = notes
    }

    /// Distance and where it came from, resolved in one place so every caller agrees.
    ///
    /// A surface leg with no length of its own, which its mode's network can measure
    /// (R-PATH-2, D-30). A catalogue route's length, a transit line's and the user's own
    /// figure all come first.
    public var needsTrackMeasurement: Bool {
        mode.trackKind != nil && transitLineID == nil && distanceKmOverride == nil
            && storedPathLengthKm == nil
    }

    /// Its length was measured along its mode's network rather than taken from a
    /// catalogue route.
    public var isMeasuredAlongTrack: Bool {
        mode.trackKind != nil && transitLineID == nil && networkVersion != nil
            && storedPathLengthKm != nil
    }

    /// Order: the user's override, then a real stored path, then the great circle —
    /// exact for a flight, flagged approximate for anything that should have followed
    /// the ground (R-PATH-5).
    public var distance: (kilometres: Double, source: DistanceSource) {
        if let override = distanceKmOverride, override >= 0 {
            return (override, .userOverride)
        }
        if let stored = storedPathLengthKm, stored >= 0 {
            return (stored, .storedPath)
        }
        guard let from = origin.coordinate, let to = destination.coordinate else {
            return (0, .unavailable)
        }
        let kilometres = GreatCircle.distanceKm(from: from, to: to)
        return (kilometres, mode.greatCircleIsExact ? .greatCircleExact : .greatCircleApproximate)
    }

    public var distanceKm: Double {
        distance.kilometres
    }

    public var distanceSource: DistanceSource {
        distance.source
    }

    /// The great-circle distance between the two ends, whatever path the leg took.
    /// Used as the comparison flight for the carbon stat (R-CO2-2).
    public var greatCircleKm: Double? {
        guard let from = origin.coordinate, let to = destination.coordinate else { return nil }
        return GreatCircle.distanceKm(from: from, to: to)
    }

    /// How long the leg took, and where that figure came from.
    ///
    /// The user's own figure wins; otherwise departure and arrival are each read in
    /// their own place's zone, so a flight from Oslo at 09:00 landing in New York at
    /// 11:30 took 8 h 30 m, not 2 h 30 m. Without both zones there is no duration —
    /// the wall-clock difference would be wrong by the zone gap, and silently so.
    public var duration: Result<(minutes: Int, source: DurationSource), DurationUnavailable> {
        if let override = durationMinutesOverride, override >= 0 {
            return .success((override, .userOverride))
        }
        let candidates: [(LocalDateTime?, LocalDateTime?, DurationSource)] = [
            (times.actualDeparture, times.actualArrival, .actualTimes),
            (times.scheduledDeparture, times.scheduledArrival, .scheduledTimes),
        ]
        var reason = DurationUnavailableReason.noTimes
        for (departure, arrival, source) in candidates {
            guard let departure, let arrival else { continue }
            guard let minutes = Self.minutes(
                from: departure, in: origin,
                to: arrival, in: destination
            ) else {
                reason = .missingTimeZone
                continue
            }
            guard minutes >= 0 else {
                reason = .arrivesBeforeDeparture
                continue
            }
            return .success((minutes, source))
        }
        return .failure(DurationUnavailable(reason: reason))
    }

    public var durationMinutes: Int? {
        try? duration.get().minutes
    }

    /// Minutes between two local times at two places, each read in its own zone. Where
    /// both ends are the same place no zone is needed: the wall clocks agree.
    static func minutes(
        from start: LocalDateTime,
        in startPlace: PlaceReference,
        to end: LocalDateTime,
        in endPlace: PlaceReference
    ) -> Int? {
        if let startZone = startPlace.timeZone, let endZone = endPlace.timeZone,
           let startInstant = start.instant(in: startZone),
           let endInstant = end.instant(in: endZone) {
            return Int((endInstant.timeIntervalSince(startInstant) / 60).rounded())
        }
        let sameZone = startPlace.id == endPlace.id
            || (startPlace.timeZoneIdentifier != nil
                && startPlace.timeZoneIdentifier == endPlace.timeZoneIdentifier)
        return sameZone ? end.wallClockMinutes - start.wallClockMinutes : nil
    }

    /// Whether the leg ran overnight: a sleeper or couchette class, or an arrival on a
    /// later calendar day than the departure (R-ACH-2, "first overnight train").
    public var isOvernight: Bool {
        if let travelClass = travelClass?.lowercased(),
           travelClass.contains("sleeper") || travelClass.contains("couchette")
           || travelClass.contains("berth") {
            return true
        }
        guard let departure = times.bestDeparture, let arrival = times.bestArrival else {
            return false
        }
        return arrival.date > departure.date
    }

    /// The arc to draw on the globe. A flight curves; anything else is a straight
    /// stand-in until a real path exists.
    public func pathForDisplay(segments: Int = 64) -> [Coordinate] {
        guard let from = origin.coordinate, let to = destination.coordinate else { return [] }
        return GreatCircle.arc(from: from, to: to, segments: segments)
    }

    /// A copy for riding the same leg again (R-JLOG-6): a new identity and the given
    /// date, everything personal to the original ride — times, seat, rating, notes —
    /// left behind.
    public func rideAgain(on date: FlexibleDate) -> JourneyLeg {
        JourneyLeg(
            mode: mode,
            origin: origin,
            destination: destination,
            date: date,
            purpose: purpose,
            storedPathLengthKm: storedPathLengthKm,
            distanceKmOverride: distanceKmOverride,
            routeID: routeID,
            routeName: routeName,
            transitLineID: transitLineID,
            networkVersion: networkVersion,
            operatorName: operatorName,
            serviceNumber: serviceNumber,
            vehicle: vehicle,
            travelClass: travelClass
        )
    }
}

/// A duration that could not be worked out, and why.
public struct DurationUnavailable: Error, Hashable, Sendable {
    public let reason: DurationUnavailableReason
}

extension JourneyLeg: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, mode, origin, destination, date, purpose, storedPathLengthKm
        case distanceKmOverride, durationMinutesOverride, times, missedConnection
        case routeID, routeName, transitLineID, networkVersion
        case operatorName, serviceNumber, vehicle, registration
        case travelClass, seat, rating, notes
    }

    /// Fields added after the first export format default when absent, so a file
    /// exported by an earlier build still imports.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            mode: container.decode(TravelMode.self, forKey: .mode),
            origin: container.decode(PlaceReference.self, forKey: .origin),
            destination: container.decode(PlaceReference.self, forKey: .destination),
            date: container.decodeIfPresent(FlexibleDate.self, forKey: .date) ?? .unknown,
            purpose: container.decodeIfPresent(TripPurpose.self, forKey: .purpose) ?? .leisure,
            storedPathLengthKm: container.decodeIfPresent(Double.self, forKey: .storedPathLengthKm),
            distanceKmOverride: container.decodeIfPresent(Double.self, forKey: .distanceKmOverride),
            durationMinutesOverride: container.decodeIfPresent(
                Int.self,
                forKey: .durationMinutesOverride
            ),
            times: container.decodeIfPresent(LegTimes.self, forKey: .times) ?? .none,
            missedConnection: container.decodeIfPresent(Bool.self, forKey: .missedConnection)
                ?? false,
            routeID: container.decodeIfPresent(Int64.self, forKey: .routeID),
            routeName: container.decodeIfPresent(String.self, forKey: .routeName),
            transitLineID: container.decodeIfPresent(Int64.self, forKey: .transitLineID),
            networkVersion: container.decodeIfPresent(String.self, forKey: .networkVersion),
            operatorName: container.decodeIfPresent(String.self, forKey: .operatorName),
            serviceNumber: container.decodeIfPresent(String.self, forKey: .serviceNumber),
            vehicle: container.decodeIfPresent(String.self, forKey: .vehicle),
            registration: container.decodeIfPresent(String.self, forKey: .registration),
            travelClass: container.decodeIfPresent(String.self, forKey: .travelClass),
            seat: container.decodeIfPresent(String.self, forKey: .seat),
            rating: container.decodeIfPresent(Int.self, forKey: .rating),
            notes: container.decodeIfPresent(String.self, forKey: .notes)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(mode, forKey: .mode)
        try container.encode(origin, forKey: .origin)
        try container.encode(destination, forKey: .destination)
        try container.encode(date, forKey: .date)
        try container.encode(purpose, forKey: .purpose)
        try container.encodeIfPresent(storedPathLengthKm, forKey: .storedPathLengthKm)
        try container.encodeIfPresent(distanceKmOverride, forKey: .distanceKmOverride)
        try container.encodeIfPresent(durationMinutesOverride, forKey: .durationMinutesOverride)
        try container.encode(times, forKey: .times)
        try container.encode(missedConnection, forKey: .missedConnection)
        try container.encodeIfPresent(routeID, forKey: .routeID)
        try container.encodeIfPresent(routeName, forKey: .routeName)
        try container.encodeIfPresent(transitLineID, forKey: .transitLineID)
        try container.encodeIfPresent(networkVersion, forKey: .networkVersion)
        try container.encodeIfPresent(operatorName, forKey: .operatorName)
        try container.encodeIfPresent(serviceNumber, forKey: .serviceNumber)
        try container.encodeIfPresent(vehicle, forKey: .vehicle)
        try container.encodeIfPresent(registration, forKey: .registration)
        try container.encodeIfPresent(travelClass, forKey: .travelClass)
        try container.encodeIfPresent(seat, forKey: .seat)
        try container.encodeIfPresent(rating, forKey: .rating)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}
