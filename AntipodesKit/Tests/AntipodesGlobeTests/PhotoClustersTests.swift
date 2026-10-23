import AntipodesCore
@testable import AntipodesGlobe
import Foundation
import Testing

@Suite("Photo clusters")
struct PhotoClustersTests {
    static func photo(_ id: String, _ latitude: Double, _ longitude: Double) -> PhotoPoint {
        PhotoPoint(
            id: id,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            takenAt: Date(timeIntervalSince1970: Double(id.hashValue & 0xFFFF))
        )
    }

    /// Oslo and Drammen are 40 km apart: one bubble from across the world, two up close.
    @Test("Nearby photos share a bubble far out and part as the globe zooms in")
    func bands() {
        let photos = [
            Self.photo("oslo-1", 59.91, 10.75),
            Self.photo("oslo-2", 59.92, 10.74),
            Self.photo("drammen", 59.74, 10.20),
            Self.photo("tokyo", 35.68, 139.77),
        ]
        let clusters = PhotoClusters(photos)
        #expect(clusters.clusters(forZoom: 1).count == 2)
        #expect(clusters.clusters(forZoom: 16).count == 3)
        #expect(clusters.photoCount == 4)
        let oslo = clusters.clusters(forZoom: 16).first { $0.photoIDs.contains("oslo-1") }
        #expect(oslo?.count == 2)
    }

    @Test("A bubble sits in the middle of its photos, not at its cell's corner")
    func centre() throws {
        let clusters = PhotoClusters([Self.photo("a", 59.0, 10.0), Self.photo("b", 59.0, 11.0)])
        let only = try #require(clusters.clusters(forZoom: 1).first)
        #expect(abs(only.coordinate.longitude - 10.5) < 0.01)
    }

    @Test("A cell keeps its identity, so a chosen bubble survives a rebuild")
    func stableIdentity() {
        let first = PhotoClusters([Self.photo("a", 48.85, 2.35)])
        let second = PhotoClusters([Self.photo("a", 48.85, 2.35), Self.photo("b", 48.86, 2.34)])
        #expect(first.clusters(forZoom: 4).first?.id == second.clusters(forZoom: 4).first?.id)
    }

    @Test("Zoom maps to bands, finer each time it doubles, never past the last")
    func zoomBands() {
        #expect(PhotoClusters.band(forZoom: 1) == 0)
        #expect(PhotoClusters.band(forZoom: 2) == 1)
        #expect(PhotoClusters.band(forZoom: 3.9) == 1)
        #expect(PhotoClusters.band(forZoom: 1000) == PhotoClusters.bandDegrees.count - 1)
    }

    /// 63.99° and 64.01° N straddle a cell edge at every band; they are one place.
    @Test("Photos either side of a cell's edge share a bubble")
    func cellEdges() {
        let clusters = PhotoClusters([Self.photo("a", 63.99, -21.0), Self.photo("b", 64.01, -21.0)])
        #expect(clusters.levels.allSatisfy { $0.count == 1 })
    }

    @Test("Photos either side of the date line stay apart")
    func dateLine() {
        let clusters = PhotoClusters([
            Self.photo("fiji", -17.7, 179.9),
            Self.photo("samoa", -13.8, -171.8),
        ])
        #expect(clusters.clusters(forZoom: 1).count == 2)
    }
}
