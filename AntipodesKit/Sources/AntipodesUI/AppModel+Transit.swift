import AntipodesCore
import AntipodesPlaces
import Foundation

/// City transit from both sources as one: the place database's metro systems, from
/// Wikidata (D-29), and the route pack's metro, tram, light-rail and bus systems, from
/// OpenStreetMap (D-36). Their ids never meet, so each id says where to ask.
extension AppModel {
    /// Every system, by city and then name.
    func allTransitSystems() async -> [TransitSystemInfo] {
        let bundled = await (try? places?.transitSystems()) ?? []
        let packed = await (try? routePack?.transitSystems()) ?? []
        return (bundled + packed).sorted {
            ($0.cityName ?? "", $0.name) < ($1.cityName ?? "", $1.name)
        }
    }

    /// One system's network, for the picker.
    func transitNetwork(forSystem system: Int64) async -> TransitNetwork? {
        if TransitNetwork.isFromRoutePack(system) {
            return try? await routePack?.transitNetwork(systems: [system])
        }
        return try? await places?.transitNetwork(systems: [system])
    }

    /// The networks of every system these lines belong to, from both sources, as one.
    func transitNetwork(forLines lines: Set<Int64>) async -> TransitNetwork {
        let packed = lines.filter(TransitNetwork.isFromRoutePack)
        let bundled = lines.subtracting(packed)
        var network = TransitNetwork.empty
        if !bundled.isEmpty, let places,
           let systems = try? await places.transitSystems(ofLines: bundled),
           let found = try? await places.transitNetwork(systems: systems) {
            network = network.merged(with: found)
        }
        if !packed.isEmpty, let routePack,
           let systems = try? await routePack.transitSystems(ofLines: packed),
           let found = try? await routePack.transitNetwork(systems: systems) {
            network = network.merged(with: found)
        }
        return network
    }

    /// A stop as a place a leg can start or end at. A route-pack stop takes its country,
    /// city and time zone from the nearest bundled town, so a ride's duration can be
    /// worked out like any other.
    func transitStopPlace(
        _ stop: Int64,
        in network: TransitNetwork?,
        system: TransitSystemInfo
    ) async
        -> PlaceReference? {
        guard TransitNetwork.isFromRoutePack(stop) else {
            return try? await places?.transitStopPlace(id: stop)
        }
        guard let found = network?.stops[stop] else { return nil }
        let town = await nearestCity(to: found.coordinate, withinKm: 40)
        return PlaceReference(
            id: .database(.station, stop),
            kind: .station,
            name: found.name,
            coordinate: found.coordinate,
            countryCode: town?.countryCode ?? system.countryCode,
            countryName: town?.countryName,
            continent: town?.continent,
            regionCode: town?.regionCode,
            regionName: town?.regionName,
            cityID: town?.impliedCityID,
            cityName: town?.name ?? system.cityName,
            timeZoneIdentifier: town?.timeZoneIdentifier
        )
    }

    /// The drawn shape of each line ridden, where the route pack has one (R-TRAN-1).
    func transitShapes(forLines lines: Set<Int64>) async -> [Int64: [[Coordinate]]] {
        guard let routePack, !lines.isEmpty else { return [:] }
        return await (try? routePack.transitShapes(lines: lines)) ?? [:]
    }
}
