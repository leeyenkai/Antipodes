import AntipodesCore
import AntipodesGlobe
import SwiftUI

/// A small, still globe framed on part of the log: a trip's thumbnail, a journey's
/// header, a place's location. Drawn from bundled outlines like the main globe, so it
/// fetches nothing (D-5).
struct MiniGlobe: View {
    @Environment(GlobeBorderStore.self) private var borderStore
    let scene: GlobeScene
    var focus: [Coordinate] = []
    var maximumZoom: Double = 6

    var body: some View {
        GlobeCanvas(
            scene: scene,
            borders: borderStore.coarse,
            camera: camera,
            selection: nil,
            palette: GlobePalette()
        )
        .background(Palette.space)
        .accessibilityHidden(true)
    }

    private var camera: GlobeCamera {
        let points = focus.isEmpty
            ? scene.pins.map(\.coordinate) + scene.arcs
            .flatMap { [$0.path.first, $0.path.last].compactMap(\.self) }
            : focus
        return GlobeCamera.framing(points, maximumZoom: maximumZoom) ?? .default
    }
}

extension MiniGlobe {
    /// A thumbnail of one trip.
    @MainActor
    static func trip(_ tripID: UUID, model: AppModel) -> MiniGlobe {
        let scene: GlobeScene
        if let cached = model.tripSceneCache[tripID],
           cached.revision == model.logRevision, cached.rules == model.rules {
            scene = cached.scene
        } else {
            scene = model.globeScene(of: model.log.restricted(toTrip: tripID), arcSegments: 24)
            model.tripSceneCache[tripID] = (model.logRevision, model.rules, scene)
        }
        // Framed on the places, not the flights there: a trip to Japan is about Japan,
        // and framing the long-haul arc would shrink it to a dot.
        let places = scene.pins.filter(\.style.isTravel).map(\.coordinate)
        return MiniGlobe(scene: scene, focus: places, maximumZoom: 6)
    }

    /// One place, close up.
    static func place(_ place: PlaceReference) -> MiniGlobe {
        let pins: [Visit] = [Visit(place: place)]
        return MiniGlobe(
            scene: GlobeSceneBuilder.build(log: TravelLog(visits: pins), rules: .default),
            maximumZoom: 5
        )
    }

    /// One journey's arcs.
    @MainActor
    static func journey(_ journey: Journey, model: AppModel) -> MiniGlobe {
        MiniGlobe(scene: model.globeScene(of: TravelLog(journeys: [journey])))
    }
}
