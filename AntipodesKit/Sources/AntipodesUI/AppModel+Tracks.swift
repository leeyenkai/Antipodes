import AntipodesCore
import AntipodesGlobe
import Foundation

/// Surface legs measured along railways, roads and ferry routes, and drawn along them
/// (R-PATH-2, R-PATH-5, D-30); hikes and rides along marked trails, cable cars along
/// their lifts, catalogue routes and transit rides along their real shapes (D-36).
extension AppModel {
    /// Measures every rail, road and ferry leg that has no length of its own, and finds
    /// the line each is drawn along.
    ///
    /// A leg is measured once: its length and the network's version are saved with it,
    /// as a transit ride's are (R-TRAN-4), so a newer map does not move an old figure.
    /// Legs logged before the networks existed, imported, or seeded are measured here;
    /// the journey editor measures a leg as its ends are picked.
    func refreshTracks() async {
        // At launch the log is reloaded and its facts refreshed from more than one
        // place; a second request while one runs is folded into one more pass, so the
        // same legs are not searched twice side by side.
        if isMeasuringTracks {
            tracksNeedAnotherPass = true
            return
        }
        isMeasuringTracks = true
        defer { isMeasuringTracks = false }
        repeat {
            tracksNeedAnotherPass = false
            await measurePendingTracks()
        } while tracksNeedAnotherPass
    }

    private func measurePendingTracks() async {
        let surface = log.allLegs.filter { $0.trackKind != nil && $0.recordedTrack == nil }
        let live = Set(surface.map(\.id))
        measuredEnds = measuredEnds.filter { live.contains($0.key) }
        countriesAlong = countriesAlong.filter { live.contains($0.key) }
        if measuredPaths.keys.contains(where: { !live.contains($0) }) {
            measuredPaths = measuredPaths.filter { live.contains($0.key) }
        }
        let pending = surface.filter { measuredEnds[$0.id] != Self.ends(of: $0) }
        guard !pending.isEmpty else { return }
        var networks: [UUID: TrackNetwork] = [:]
        for leg in pending {
            networks[leg.id] = await trackNetwork(
                for: leg.trackKind,
                from: leg.origin.coordinate,
                to: leg.destination.coordinate
            )
        }
        guard !networks.isEmpty else { return }
        await preloadBorders()
        let borders = borders

        let found = await Task.detached(priority: .utility) {
            pending.compactMap { leg -> TrackMeasurement? in
                guard let network = networks[leg.id] else { return nil }
                let path = Self.route(leg, on: network)
                return TrackMeasurement(
                    id: leg.id,
                    ends: Self.ends(of: leg),
                    path: path,
                    version: network.version,
                    countries: borders.flatMap { borders in
                        path?.countries { borders.countryCode(at: $0) }
                    }
                )
            }
        }.value
        var paths = measuredPaths
        for measurement in found {
            measuredEnds[measurement.id] = measurement.ends
            paths[measurement.id] = measurement.path?.coordinates
            countriesAlong[measurement.id] = measurement.countries
        }
        measuredPaths = paths
        tripSceneCache = [:]
        recompute()
        saveTrackLengths(found)
    }

    /// Every leg drawn along its line rather than its great circle, the best known way
    /// first: the track the user's device recorded, a catalogue route's real shape, the
    /// network it was measured along, and a transit ride's line through its stops.
    var trackPaths: [UUID: [Coordinate]] {
        var paths = transitPaths
        paths.merge(measuredPaths) { _, measured in measured }
        paths.merge(routePaths) { _, shaped in shaped }
        for leg in log.allLegs {
            if let track = leg.recordedTrack {
                paths[leg.id] = track.points
            }
        }
        return paths
    }

    /// A globe scene of part of the log, its legs drawn along their track.
    func globeScene(
        of log: TravelLog,
        arcSegments: Int = GlobeSceneBuilder.defaultArcSegments
    ) -> GlobeScene {
        GlobeSceneBuilder.build(log: log, rules: rules, arcSegments: arcSegments, paths: trackPaths)
    }

    /// Each transit ride on a known line drawn along the line's shape between its two
    /// stops where the route pack has one, and otherwise from stop to stop through those
    /// it passed (R-TRAN-1) — never as a straight dash.
    func refreshTransitPaths() {
        var paths: [UUID: [Coordinate]] = [:]
        for leg in log.allLegs where leg.mode == .cityTransit {
            guard let line = leg.transitLineID else { continue }
            if let shape = transitShapes[line],
               let from = leg.origin.coordinate, let to = leg.destination.coordinate,
               let path = Polyline.slice(among: shape, from: from, to: to, toleranceKm: 0.6) {
                paths[leg.id] = path
                continue
            }
            guard case let .database(.station, start) = leg.origin.id,
                  case let .database(.station, end) = leg.destination.id,
                  let stops = transitNetwork.route(onLine: line, from: start, to: end)
            else { continue }
            let coordinates = stops.compactMap(transitNetwork.coordinate(of:))
            if coordinates.count == stops.count {
                paths[leg.id] = coordinates
            }
        }
        if paths != transitPaths {
            transitPaths = paths
            tripSceneCache = [:]
        }
    }

    /// Each catalogue route ridden drawn along its real shape from the route pack, cut
    /// between the stations the leg rode between (R-JLOG-3, R-PATH-1).
    func refreshRoutePaths() async {
        guard let routePack else { return }
        var paths: [UUID: [Coordinate]] = [:]
        for leg in log.allLegs {
            guard let route = leg.routeID else { continue }
            if routeShapes[route] == nil {
                routeShapes[route] = await (try? routePack.routeShape(route)) ?? []
            }
            guard let shape = routeShapes[route], !shape.isEmpty else { continue }
            if let from = leg.origin.coordinate, let to = leg.destination.coordinate,
               let path = Polyline.slice(among: shape, from: from, to: to, toleranceKm: 15) {
                paths[leg.id] = path
            } else if shape.count == 1 {
                // Ends the shape does not reach — a city's centre far from its station —
                // still ride the whole route.
                paths[leg.id] = shape[0]
            }
        }
        if paths != routePaths {
            routePaths = paths
            tripSceneCache = [:]
        }
    }

    /// The network a leg of this kind between these places is measured along: the
    /// place database's for rail, road and ferry, the lifts', or the marked trails of
    /// the region both ends are in (D-36).
    func trackNetwork(
        for kind: TrackKind?,
        from: Coordinate?,
        to: Coordinate?
    ) async -> TrackNetwork? {
        guard let kind else { return nil }
        guard kind.isTrail else { return await loadTrackNetwork(kind) }
        guard let from, let to, let routePack else { return nil }
        if trailRegions == nil {
            trailRegions = await (try? routePack.trailRegions()) ?? []
        }
        guard let region = trailRegions?.first(where: {
            $0.kind == kind && $0.contains(from) && $0.contains(to)
        }) else { return nil }
        if let network = trailNetworks[region.network] {
            return network
        }
        guard let loaded = try? await routePack.trailNetwork(region) else { return nil }
        // A region's trails are hundreds of thousands of edges; keep the last two.
        if trailNetworks.count >= 2 {
            trailNetworks.removeAll()
        }
        trailNetworks[region.network] = loaded
        return loaded
    }

    /// A network, read from the database the first time it is asked for.
    func loadTrackNetwork(_ kind: TrackKind) async -> TrackNetwork? {
        if let network = trackNetworks[kind] {
            return network
        }
        let loaded: TrackNetwork? = if kind == .lift {
            await (try? routePack?.liftNetwork())
        } else {
            await (try? places?.trackNetwork(kind))
        }
        guard let loaded else { return nil }
        if trackNetworks[kind] == nil {
            trackNetworks[kind] = loaded
        }
        return trackNetworks[kind]
    }

    /// Every network, loaded in the background so the journey editor can measure a leg
    /// as soon as its ends are picked.
    func preloadTrackNetworks() async {
        for kind in TrackKind.bundled + [.lift] {
            _ = await loadTrackNetwork(kind)
        }
    }

    /// Saves the length of each measured leg that still needs one, against the log as
    /// it is now: a leg edited while the network was searched keeps the edit.
    private func saveTrackLengths(_ found: [TrackMeasurement]) {
        let measured = Dictionary(
            found.filter { $0.path != nil }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var edited: [Journey] = []
        for var journey in log.journeys {
            var changed = false
            for index in journey.legs.indices {
                let leg = journey.legs[index]
                guard leg.needsTrackMeasurement,
                      let item = measured[leg.id], let path = item.path,
                      item.ends == Self.ends(of: leg)
                else { continue }
                journey.legs[index].storedPathLengthKm = path.lengthKm
                journey.legs[index].networkVersion = item.version
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

    nonisolated static func route(_ leg: JourneyLeg, on network: TrackNetwork) -> TrackPath? {
        network.route(for: leg)
    }
}

/// What its network said about one leg.
struct TrackMeasurement: Sendable {
    let id: UUID
    let ends: [Coordinate]
    let path: TrackPath?
    let version: String
    /// The countries its line runs through, in order (R-PATH-6).
    let countries: [String]?
}

extension LegDraft {
    /// The draft measured along its network, worked out off the main actor: two ends
    /// the network cannot join make the search explore all of it, which would stall
    /// the form the user is typing in.
    static func measured(_ draft: LegDraft, model: AppModel) async -> LegDraft {
        let network = await model.trackNetwork(
            for: draft.trackKind,
            from: draft.origin?.coordinate,
            to: draft.destination?.coordinate
        )
        return await Task.detached(priority: .userInitiated) {
            var copy = draft
            copy.measureAlongTracks(network)
            return copy
        }.value
    }

    /// Takes the length found for `original`, if this draft is still the leg that was
    /// measured: the user may have changed an end or the mode while it was worked out.
    mutating func adoptMeasurement(_ measured: LegDraft, madeFrom original: LegDraft) {
        guard mode == original.mode, activity == original.activity,
              origin?.id == original.origin?.id,
              destination?.id == original.destination?.id,
              transitLineID == original.transitLineID, routeID == original.routeID,
              distanceOverrideKm == original.distanceOverrideKm else { return }
        storedPathLengthKm = measured.storedPathLengthKm
        networkVersion = measured.networkVersion
    }

    /// A surface leg with no length of its own is measured along its network as its
    /// ends are picked (D-30, D-36); one that stops being such a leg, or whose ends the
    /// network does not join, drops a length it was given that way.
    mutating func measureAlongTracks(_ network: TrackNetwork?) {
        let wasMeasured = networkVersion != nil && transitLineID == nil
        let network = network.flatMap { $0.kind == trackKind ? $0 : nil }
        var path: TrackPath?
        if let network, transitLineID == nil, distanceOverrideKm == nil, recordedTrack == nil,
           storedPathLengthKm == nil || wasMeasured,
           let from = origin?.coordinate, let to = destination?.coordinate {
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
