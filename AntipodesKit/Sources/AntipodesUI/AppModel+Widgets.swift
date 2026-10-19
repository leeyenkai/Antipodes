import AntipodesCore
import AntipodesGlobe
import AntipodesPlaces
import AntipodesStats
import Foundation
import SwiftUI
#if os(iOS)
    import WidgetKit
#endif

extension AppModel {
    // MARK: - Widgets

    /// Writes what the Home and Lock Screen widgets show into the shared container.
    ///
    /// Widgets are an iOS extension only. On the Mac there is nothing to write for, and
    /// touching a group container there would ask the user for access to other apps'
    /// data, so this does nothing.
    func writeWidgetSnapshot() {
        #if os(iOS)
            let statistics = statistics
            let today = CalendarDate.today()
            let snapshot = WidgetSnapshot(
                generatedAt: Date(),
                countries: statistics.coverage.listedCountriesVisited,
                worldPercent: statistics.coverage.worldFraction * 100,
                countryListName: rules.countryList.displayName,
                continents: statistics.coverage.continentsVisited,
                distanceText: Format.distance(statistics.distance.totalKm, rules.unitSystem),
                placesLogged: log.visits.count,
                memoriesDay: today.iso,
                memories: statistics.time.onThisDay.prefix(3).map { entry in
                    switch entry.record {
                    case let .visit(visit):
                        WidgetSnapshot.Memory(
                            title: visit.place.name,
                            subtitle: visit.visitType.displayName,
                            yearsAgo: entry.yearsAgo
                        )
                    case let .leg(leg):
                        WidgetSnapshot.Memory(
                            title: "\(leg.origin.shortName) → \(leg.destination.shortName)",
                            subtitle: leg.mode.displayName,
                            yearsAgo: entry.yearsAgo
                        )
                    }
                },
                collections: statistics.collections.map {
                    WidgetSnapshot.CollectionSummary(
                        id: $0.id,
                        name: $0.definition.name,
                        symbol: $0.definition.symbol,
                        visited: $0.visitedCount,
                        total: $0.total
                    )
                }
            )
            try? snapshot.save()
            writeWidgetGlobe()
            WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    #if os(iOS)
        /// Renders the globe the Globe widget shows. Rendering takes a few tens of
        /// milliseconds on the main actor, so it is skipped when the shaded countries and
        /// the pins and arcs are the same as last time.
        private func writeWidgetGlobe() {
            guard let url = WidgetSnapshot.containerURL()?
                .appending(path: WidgetSnapshot.globeImageName) else { return }
            let scene = GlobeSceneBuilder.build(log: log, rules: rules, home: home, arcSegments: 24)
            var hasher = Hasher()
            hasher.combine(scene.shadedCountryCodes)
            hasher.combine(scene.pins.count)
            hasher.combine(scene.arcs.count)
            hasher.combine(home?.name)
            let signature = hasher.finalize()
            guard signature != widgetGlobeSignature else { return }

            let globe = GlobeCanvas(
                scene: scene,
                borders: globeBorders,
                camera: scene.focusCoordinate.map { GlobeCamera(centre: $0, zoom: 1) } ?? .default,
                selection: nil,
                palette: GlobePalette(),
                rendersAsynchronously: false
            )
            .frame(width: 340, height: 340)
            .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: globe)
            renderer.scale = 3
            guard let data = renderer.uiImage?.pngData() else { return }
            do {
                try data.write(to: url, options: .atomic)
                widgetGlobeSignature = signature
            } catch {
                // The widget falls back to a plain globe symbol; nothing for the user to do.
            }
        }
    #endif
}
