import AntipodesCore
import AntipodesGlobe
import AntipodesPlaces
import AntipodesStats
import Foundation
import SwiftUI

public extension AppModel {
    // MARK: - Search

    func search(_ text: String, kinds: Set<PlaceKind>?) async -> [PlaceSearchResult] {
        guard let places, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return await (try? places.search(text, kinds: kinds, limit: 40)) ?? []
    }

    func airport(code: String) async -> PlaceReference? {
        await (try? places?.airport(code: code))?.placeReference
    }

    func nearestCity(
        to coordinate: Coordinate,
        withinKm radius: Double = 40
    ) async -> PlaceReference? {
        await (try? places?.nearestCity(to: coordinate, withinKm: radius))?.placeReference
    }

    func route(id: Int64) -> RouteInfo? {
        catalogue.routes.first { $0.id == id }
    }

    /// Turns a dropped pin into a place that counts (R-LOG-5).
    ///
    /// The country comes from point-in-polygon against the bundled borders — the same
    /// outlines the globe shades — and its name and continent from the database. The
    /// region and time zone are taken from the nearest bundled city in that country, if
    /// one is within 30 km; further out the pin keeps only its country rather than
    /// borrowing a region it may not be in, and takes the country's zone only where the
    /// whole country keeps one (D-13). Nothing leaves the device.
    func resolvePin(at coordinate: Coordinate, name: String) async -> PlaceReference {
        let borders = loadBorders()
        let code = borders?.countryCode(near: coordinate, toleranceKm: 25)
        let country = code.flatMap { catalogue.countries[$0] }
        var region: (code: String?, name: String?, zone: String?) = (nil, nil, nil)
        if let city = await nearestCity(to: coordinate, withinKm: 30), city.countryCode == code {
            region = (city.regionCode, city.regionName, city.timeZoneIdentifier)
        }
        var zone = region.zone
        if zone == nil, let code {
            zone = await (try? places?.singleTimeZone(country: code))
        }
        return PlaceReference(
            id: .custom(UUID()),
            kind: .custom,
            name: name,
            coordinate: coordinate,
            countryCode: code,
            countryName: country?.name,
            continent: country?.continent,
            regionCode: region.code,
            regionName: region.name,
            timeZoneIdentifier: zone
        )
    }

    /// The 1:50m outlines, for pin lookup and share cards. Preloaded off the main thread
    /// at launch (`preloadBorders`); loaded here on first use if that has not finished.
    var globeBorders: CountryBorders? {
        loadBorders()
    }

    /// Decodes the 1:50m outlines in the background, so the first dropped pin or share
    /// card does not stall the screen for the ~70 ms it takes.
    func preloadBorders() async {
        guard borders == nil, let bordersURL else { return }
        let loaded = await Task.detached(priority: .utility) {
            try? CountryBorders.load(from: bordersURL)
        }.value
        if borders == nil {
            borders = loaded
        }
    }

    private func loadBorders() -> CountryBorders? {
        if let borders {
            return borders
        }
        guard let bordersURL else { return nil }
        borders = try? CountryBorders.load(from: bordersURL)
        return borders
    }
}
