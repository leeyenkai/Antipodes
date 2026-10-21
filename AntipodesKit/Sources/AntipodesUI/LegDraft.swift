import AntipodesCore
import Foundation

/// A leg while it is being entered or edited. Only mode and the two ends are required
/// (R-LEG-1); the rest stays empty until the user adds it (R-LEG-2).
struct LegDraft: Identifiable, Equatable {
    var id = UUID()
    var mode: TravelMode
    var origin: PlaceReference?
    var destination: PlaceReference?
    var date: FlexibleDate = .day(.today())
    var purpose: TripPurpose = .leisure
    var times = LegTimes.none
    var missedConnection = false
    var routeID: Int64?
    var routeName: String?
    /// The transit line ridden and the network it was picked from (R-JLOG-5, R-TRAN-4).
    var transitLineID: Int64?
    var networkVersion: String?
    var storedPathLengthKm: Double?
    /// The user's own distance, in kilometres, kept exactly as given.
    var distanceOverrideKm: Double?
    var durationOverrideMinutes: Int?
    var operatorName = ""
    var serviceNumber = ""
    var vehicle = ""
    var registration = ""
    var travelClass = ""
    var seat = ""
    var rating: Int?
    var notes = ""

    init(mode: TravelMode) {
        self.mode = mode
    }

    init(leg: JourneyLeg) {
        id = leg.id
        mode = leg.mode
        origin = leg.origin
        destination = leg.destination
        date = leg.date
        purpose = leg.purpose
        times = leg.times
        missedConnection = leg.missedConnection
        routeID = leg.routeID
        routeName = leg.routeName
        transitLineID = leg.transitLineID
        networkVersion = leg.networkVersion
        storedPathLengthKm = leg.storedPathLengthKm
        distanceOverrideKm = leg.distanceKmOverride
        durationOverrideMinutes = leg.durationMinutesOverride
        operatorName = leg.operatorName ?? ""
        serviceNumber = leg.serviceNumber ?? ""
        vehicle = leg.vehicle ?? ""
        registration = leg.registration ?? ""
        travelClass = leg.travelClass ?? ""
        seat = leg.seat ?? ""
        rating = leg.rating
        notes = leg.notes ?? ""
    }

    /// A draft for riding a catalogue route end to end (R-JLOG-3). The route's length is
    /// its path length, so the distance is not a straight-line stand-in.
    init(route: RouteInfo) {
        mode = route.mode
        origin = route.start
        destination = route.end
        routeID = route.id
        routeName = route.name
        storedPathLengthKm = route.lengthKm
    }

    /// The draft for the next leg of a journey: it starts where this one ended, on the
    /// same day, by the same mode (R-JLOG-4).
    func connecting() -> LegDraft {
        var next = LegDraft(mode: mode)
        next.origin = destination
        next.date = date
        next.purpose = purpose
        return next
    }

    var isComplete: Bool {
        origin != nil && destination != nil
    }

    /// The leg as it would be saved, or `nil` until both ends are set.
    var leg: JourneyLeg? {
        guard let origin, let destination else { return nil }
        return JourneyLeg(
            id: id,
            mode: mode,
            origin: origin,
            destination: destination,
            date: date,
            purpose: purpose,
            // A route's length applies only while both ends are the route's own; pick a
            // different station and the leg is a section of it, with no known length.
            storedPathLengthKm: storedPathLengthKm,
            distanceKmOverride: distanceOverrideKm.flatMap { $0 > 0 ? $0 : nil },
            durationMinutesOverride: durationOverrideMinutes,
            times: times,
            missedConnection: missedConnection,
            routeID: routeID,
            routeName: routeName,
            transitLineID: transitLineID,
            networkVersion: networkVersion,
            operatorName: operatorName.trimmedOrNil,
            serviceNumber: serviceNumber.trimmedOrNil,
            vehicle: vehicle.trimmedOrNil,
            registration: registration.trimmedOrNil,
            travelClass: travelClass.trimmedOrNil,
            seat: seat.trimmedOrNil,
            rating: rating,
            notes: notes.trimmedOrNil
        )
    }

    /// A ride picked on a transit line: its stops, its line, and the length stop to stop.
    mutating func apply(_ ride: TransitRide) {
        mode = .cityTransit
        origin = ride.origin
        destination = ride.destination
        transitLineID = ride.line.id
        networkVersion = ride.system.networkVersion
        serviceNumber = ride.line.shortName ?? ride.line.name
        storedPathLengthKm = ride.lengthKm
    }

    /// Moving an end by hand takes a ride off its line: the stops in between are no
    /// longer known, and nor is the length.
    mutating func leaveTransitLine() {
        guard transitLineID != nil else { return }
        transitLineID = nil
        networkVersion = nil
        storedPathLengthKm = nil
    }

    /// A route's catalogue length stops applying when the user moves an end away from
    /// the route's own: they rode a section, whose length the catalogue does not know.
    mutating func endpointChanged(route: RouteInfo?) {
        guard let route else { return }
        if origin?.id != route.start?.id || destination?.id != route.end?.id {
            storedPathLengthKm = nil
        } else {
            storedPathLengthKm = route.lengthKm
        }
    }

    var hasDetails: Bool {
        !times.isEmpty || !operatorName.isEmpty || !serviceNumber.isEmpty || !vehicle.isEmpty
            || !registration.isEmpty || !travelClass.isEmpty || !seat.isEmpty || rating != nil
            || !notes.isEmpty || distanceOverrideKm != nil || durationOverrideMinutes != nil
            || purpose != .leisure
    }
}

extension LocalDateTime {
    /// Reads a picked `Date` as the wall-clock time it showed. The picker shows the
    /// device's zone, and the user types the time on the ticket, so the clock reading —
    /// not the instant — is what was meant.
    init?(pickerDate: Date) {
        let parts = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: pickerDate
        )
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let date = CalendarDate(year: year, month: month, day: day)
        else { return nil }
        self.init(date: date, hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// The `Date` a picker should show for this wall-clock time.
    var pickerDate: Date {
        instant(in: .current) ?? Date()
    }
}
