import AntipodesCore
import AntipodesPlaces
import Foundation

/// A place a journey arrived at, to be logged as a visit (D-32).
public struct Arrival: Hashable, Sendable {
    public let place: PlaceReference
    public let date: FlexibleDate
}

public extension AppModel {
    /// Where arriving at `destination` is logged: the city an airport serves — a flight
    /// lands in Tokyo, not in Haneda — or the place itself.
    func arrivalPlace(for destination: PlaceReference) async -> PlaceReference {
        guard destination.kind == .airport, case let .database(.airport, row) = destination.id,
              let city = await (try? places?.city(servingAirport: row)) else { return destination }
        return city.placeReference
    }

    /// The visits new legs arrive at: the end of each run of connections, its airport
    /// resolved to a city, and none that is home or already logged on those days.
    func arrivals(for legs: [JourneyLeg]) async -> [Arrival] {
        var found: [(place: PlaceReference, date: FlexibleDate)] = []
        for leg in Arrivals.finalLegs(of: legs) {
            await found.append((arrivalPlace(for: leg.destination), Arrivals.arrivalDate(of: leg)))
        }
        return Arrivals.visits(arrivingAt: found, home: home, existing: log.visits)
            .map { Arrival(place: $0.place, date: $0.date) }
    }
}
