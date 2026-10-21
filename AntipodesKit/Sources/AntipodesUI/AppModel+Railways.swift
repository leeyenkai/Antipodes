import AntipodesCore
import AntipodesGlobe
import Foundation

/// Rail legs measured along the railway network and drawn along it (R-PATH-2,
/// R-PATH-5, D-30).
extension AppModel {
    /// Loads the network, measures every rail leg that has no length of its own, and
    /// finds the track each rail leg is drawn along.
    ///
    /// A leg is measured once: its length and the network's version are saved with it,
    /// as a transit ride's are (R-TRAN-4), so a newer map does not move an old figure.
    /// Legs logged before the network existed, imported, or seeded are measured here;
    /// the journey editor measures a leg as its ends are picked.
    func refreshRailways() async {
        guard let network = await loadRailNetwork() else { return }
        await preloadBorders()
        let borders = borders
        let rail = log.allLegs.filter { $0.mode == .rail }
        let live = Set(rail.map(\.id))
        railPathEnds = railPathEnds.filter { live.contains($0.key) }
        railCountries = railCountries.filter { live.contains($0.key) }
        if railPaths.keys.contains(where: { !live.contains($0) }) {
            railPaths = railPaths.filter { live.contains($0.key) }
        }
        let pending = rail.filter { railPathEnds[$0.id] != Self.ends(of: $0) }
        guard !pending.isEmpty else { return }

        let found = await Task.detached(priority: .utility) {
            pending.map { leg in
                let path = Self.route(leg, on: network)
                return RailMeasurement(
                    id: leg.id,
                    ends: Self.ends(of: leg),
                    path: path,
                    countries: borders.flatMap { borders in
                        path?.countries { borders.countryCode(at: $0) }
                    }
                )
            }
        }.value
        var paths = railPaths
        for measurement in found {
            railPathEnds[measurement.id] = measurement.ends
            paths[measurement.id] = measurement.path?.coordinates
            railCountries[measurement.id] = measurement.countries
        }
        railPaths = paths
        tripSceneCache = [:]
        recompute()
        saveRailLengths(found, version: network.version)
    }

    /// A globe scene of part of the log, its rail legs drawn along their track.
    func globeScene(
        of log: TravelLog,
        arcSegments: Int = GlobeSceneBuilder.defaultArcSegments
    ) -> GlobeScene {
        GlobeSceneBuilder.build(log: log, rules: rules, arcSegments: arcSegments, paths: railPaths)
    }

    /// The network, read from the database the first time it is asked for.
    func loadRailNetwork() async -> RailNetwork? {
        if let railNetwork {
            return railNetwork
        }
        guard let places else { return nil }
        let loaded = try? await places.railNetwork()
        if railNetwork == nil {
            railNetwork = loaded
        }
        return railNetwork
    }

    /// Saves the length of each measured leg that still needs one, against the log as
    /// it is now: a leg edited while the network was searched keeps the edit.
    private func saveRailLengths(_ found: [RailMeasurement], version: String) {
        let measured = Dictionary(
            found.compactMap { item in item.path.map { (item.id, (item.ends, $0.lengthKm)) } },
            uniquingKeysWith: { first, _ in first }
        )
        var edited: [Journey] = []
        for var journey in log.journeys {
            var changed = false
            for index in journey.legs.indices {
                let leg = journey.legs[index]
                guard leg.needsRailMeasurement,
                      let (ends, length) = measured[leg.id], ends == Self.ends(of: leg)
                else { continue }
                journey.legs[index].storedPathLengthKm = length
                journey.legs[index].networkVersion = version
                changed = true
            }
            if changed {
                edited.append(journey)
            }
        }
        guard !edited.isEmpty else { return }
        perform {
            for journey in edited {
                try store.updateJourney(journey)
            }
        }
    }

    nonisolated static func ends(of leg: JourneyLeg) -> [Coordinate] {
        [leg.origin.coordinate, leg.destination.coordinate].compactMap(\.self)
    }

    nonisolated static func route(_ leg: JourneyLeg, on network: RailNetwork) -> RailPath? {
        guard let origin = leg.origin.coordinate, let destination = leg.destination.coordinate
        else { return nil }
        return network.route(from: origin, to: destination)
    }
}

/// What the network said about one leg.
struct RailMeasurement: Sendable {
    let id: UUID
    let ends: [Coordinate]
    let path: RailPath?
    /// The countries its track runs through, in order (R-PATH-6).
    let countries: [String]?
}

extension LegDraft {
    /// A rail leg with no length of its own is measured along the railway network as
    /// its ends are picked (D-30); one that stops being a rail leg, or whose ends the
    /// network does not join, drops a length it was given that way.
    mutating func measureAlongRailways(_ network: RailNetwork?) {
        let wasMeasured = networkVersion != nil && transitLineID == nil
        var path: RailPath?
        if mode == .rail, transitLineID == nil, distanceOverrideKm == nil,
           storedPathLengthKm == nil || wasMeasured,
           let network, let from = origin?.coordinate, let to = destination?.coordinate {
            path = network.route(from: from, to: to)
        }
        if let path, let network {
            storedPathLengthKm = path.lengthKm
            networkVersion = network.version
        } else if wasMeasured {
            storedPathLengthKm = nil
            networkVersion = nil
        }
    }
}
