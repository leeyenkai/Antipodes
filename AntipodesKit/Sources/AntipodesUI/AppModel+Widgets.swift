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
    ///
    /// A burst of edits — an import, a run of quick changes — settles first: the write
    /// waits a moment and a newer one replaces it. Nothing is written, and the widgets
    /// are not reloaded, when the snapshot would say what the last one did.
    func writeWidgetSnapshot() {
        #if os(iOS)
            widgetWrite?.cancel()
            widgetWrite = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                writeWidgetSnapshotNow()
            }
        #endif
    }

    #if os(iOS)
        private func writeWidgetSnapshotNow() {
            let snapshot = makeWidgetSnapshot()
            let globeChanged = writeWidgetGlobe()
            if let last = lastWidgetSnapshot, last.hasSameContent(as: snapshot), !globeChanged {
                return
            }
            do {
                try snapshot.save()
                lastWidgetSnapshot = snapshot
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                // Without the app group the widgets show their placeholder; nothing for
                // the user to do.
            }
        }

        private func makeWidgetSnapshot() -> WidgetSnapshot {
            let statistics = statistics
            let today = CalendarDate.today()
            let days = (0 ..< WidgetSnapshot.memoryDayCount).compactMap { today.adding(days: $0) }
            return WidgetSnapshot(
                generatedAt: Date(),
                countries: statistics.coverage.listedCountriesVisited,
                worldPercent: statistics.coverage.worldFraction * 100,
                countryListName: rules.countryList.displayName,
                continents: statistics.coverage.continentsVisited,
                distanceText: Format.distance(statistics.distance.totalKm, rules.unitSystem),
                placesLogged: log.visits.count,
                memoryDays: days.map { day in
                    WidgetSnapshot.MemoryDay(
                        day: day.iso,
                        memories: TimeStatistics.onThisDay(log: log, today: day).prefix(3)
                            .map(widgetMemory)
                    )
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
        }

        private func widgetMemory(_ entry: OnThisDayEntry) -> WidgetSnapshot.Memory {
            switch entry.record {
            case let .visit(visit):
                WidgetSnapshot.Memory(
                    title: visit.place.name,
                    subtitle: visit.visitType.displayName,
                    year: entry.year,
                    link: DeepLink.visit(visit.id).url
                )
            case let .leg(leg):
                WidgetSnapshot.Memory(
                    title: "\(leg.origin.shortName) → \(leg.destination.shortName)",
                    subtitle: leg.mode.displayName,
                    year: entry.year,
                    link: log.journeys.first { $0.legs.contains { $0.id == leg.id } }
                        .map { DeepLink.journey($0.id).url }
                )
            }
        }
    #endif

    #if os(iOS)
        /// Renders the globe the Globe widget shows, and says whether it changed.
        /// Rendering takes a few tens of milliseconds on the main actor, so it is skipped
        /// when the shaded countries and the pins and arcs are the same as last time.
        @discardableResult
        private func writeWidgetGlobe() -> Bool {
            guard let url = WidgetSnapshot.containerURL()?
                .appending(path: WidgetSnapshot.globeImageName) else { return false }
            let scene = GlobeSceneBuilder.build(log: log, rules: rules, home: home, arcSegments: 24)
            var hasher = Hasher()
            // Where things are, not only how many: moving a visit from Paris to Lyon
            // must redraw the widget's globe.
            hasher.combine(scene.shadedCountryCodes)
            for pin in scene.pins {
                hasher.combine(pin.coordinate)
                hasher.combine(pin.style.isTravel)
            }
            for arc in scene.arcs {
                hasher.combine(arc.path.first)
                hasher.combine(arc.path.last)
            }
            hasher.combine(home?.id)
            let signature = hasher.finalize()
            guard signature != widgetGlobeSignature else { return false }

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
            guard let data = renderer.uiImage?.pngData() else { return false }
            do {
                try data.write(to: url, options: .atomic)
                widgetGlobeSignature = signature
                return true
            } catch {
                // The widget falls back to a plain globe symbol; nothing for the user to do.
                return false
            }
        }
    #endif
}
