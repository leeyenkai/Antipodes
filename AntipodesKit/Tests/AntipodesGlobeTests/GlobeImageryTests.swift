import AntipodesCore
@testable import AntipodesGlobe
import Foundation
import Testing

@Suite("Wrapping a picture of the Earth on the globe")
struct GlobeImageryTests {
    /// An 8 × 4 picture whose red channel counts columns in 30s and green counts rows in
    /// 60s, so any sampled colour says exactly where on the picture it came from. Each
    /// column is 45° of longitude and each row 45° of latitude.
    static let grid: EquirectangularImage = {
        var pixels: [UInt8] = []
        for row in 0 ..< 4 {
            for column in 0 ..< 8 {
                pixels += [UInt8(column * 30), UInt8(row * 60), 0, 255]
            }
        }
        return EquirectangularImage(width: 8, height: 4, pixels: pixels)!
    }()

    static let view = GlobeSize(width: 100, height: 100)

    /// The pixel nearest a point in the view, as red, green and alpha.
    static func sample(
        _ raster: GlobeRaster,
        x: Double,
        y: Double
    ) -> (red: Int, green: Int, alpha: Int) {
        let column = Int((x - raster.originX) * raster.scale)
        let row = Int((y - raster.originY) * raster.scale)
        let offset = (row * raster.width + column) * 4
        return (
            Int(raster.pixels[offset]),
            Int(raster.pixels[offset + 1]),
            Int(raster.pixels[offset + 3])
        )
    }

    @Test("The raster covers the disc only, clear outside it and opaque inside")
    func coverage() throws {
        let globe = OrthographicGlobe(
            camera: GlobeCamera(centre: Coordinate(latitude: 0, longitude: 0)),
            size: Self.view
        )
        let raster = try #require(globe.rasterise(Self.grid, viewSize: Self.view, scale: 1))
        // Radius 46 (100 / 2 × 0.92), so the disc spans 4 ... 96.
        #expect(raster.originX == 4)
        #expect(raster.width == 92)
        #expect(Self.sample(raster, x: 50, y: 50).alpha == 255)
        #expect(Self.sample(raster, x: 5, y: 5).alpha == 0)
        #expect(Self.sample(raster, x: 95, y: 94).alpha == 0)
    }

    /// Facing 0°, 0°: the middle of the view is the middle of the picture, between
    /// columns 3 and 4 (red 90 and 120) and rows 1 and 2 (green 60 and 120).
    @Test("The middle of the view samples the point the camera faces")
    func centre() throws {
        let globe = OrthographicGlobe(
            camera: GlobeCamera(centre: Coordinate(latitude: 0, longitude: 0)),
            size: Self.view
        )
        let raster = try #require(globe.rasterise(Self.grid, viewSize: Self.view, scale: 1))
        let middle = Self.sample(raster, x: 50, y: 50)
        #expect(abs(middle.red - 105) <= 1)
        #expect(abs(middle.green - 90) <= 1)
    }

    /// Half a radius right of centre is 30° east: column 4 + 1/6, so red 125. Half a
    /// radius up is 30° north: row 5/6, so green 50. East is right and north is up.
    @Test("East is to the right and north is up")
    func orientation() throws {
        let globe = OrthographicGlobe(
            camera: GlobeCamera(centre: Coordinate(latitude: 0, longitude: 0)),
            size: Self.view
        )
        let raster = try #require(globe.rasterise(Self.grid, viewSize: Self.view, scale: 1))
        // Pixel centres sit on half points, so these are 23.5 and 22.5 points out:
        // 30.7° east (red 125.5) and 29.3° north (green 50.9).
        let east = Self.sample(raster, x: 73.5, y: 50.5)
        #expect(abs(east.red - 125) <= 2)
        let north = Self.sample(raster, x: 50.5, y: 27.5)
        #expect(abs(north.green - 50) <= 2)
    }

    /// Facing 90° E puts the middle of the view between columns 5 and 6 (red 165).
    @Test("Turning the camera turns the picture")
    func turned() throws {
        let globe = OrthographicGlobe(
            camera: GlobeCamera(centre: Coordinate(latitude: 0, longitude: 90)),
            size: Self.view
        )
        let raster = try #require(globe.rasterise(Self.grid, viewSize: Self.view, scale: 1))
        #expect(abs(Self.sample(raster, x: 50, y: 50).red - 165) <= 1)
    }

    /// Zoomed in, the disc is bigger than the view, so the raster is the view and no
    /// more.
    @Test("Zoomed in, only the visible part is drawn")
    func zoomed() throws {
        let globe = OrthographicGlobe(
            camera: GlobeCamera(centre: Coordinate(latitude: 0, longitude: 0), zoom: 4),
            size: Self.view
        )
        let raster = try #require(globe.rasterise(Self.grid, viewSize: Self.view, scale: 2))
        #expect(raster.originX == 0)
        #expect(raster.width == 200)
        #expect(raster.height == 200)
        #expect(Self.sample(raster, x: 1, y: 1).alpha == 255)
    }

    @Test("A picture whose pixels do not match its size is refused")
    func malformed() {
        #expect(EquirectangularImage(width: 4, height: 2, pixels: [0, 0, 0]) == nil)
    }
}

@Suite("Wishlisted routes on the globe")
struct WishlistRouteSceneTests {
    /// Oslo to Bergen on the wishlist: drawn as a line, counted nowhere.
    @Test("A wishlisted route is drawn but adds no journey, distance or pin")
    func wishlistRoute() {
        let route = GlobeWishlistRoute(
            id: UUID(),
            name: "Bergen Line",
            from: Coordinate(latitude: 59.91, longitude: 10.75),
            to: Coordinate(latitude: 60.39, longitude: 5.33)
        )
        let scene = GlobeSceneBuilder.build(log: .empty, rules: .default, wishlistRoutes: [route])
        #expect(scene.wishlistRoutes.count == 1)
        #expect(scene.wishlistRoutes.first?.path.count == 33)
        #expect(scene.arcs.isEmpty)
        #expect(scene.pins.isEmpty)
        #expect(scene.totalDistanceKm == 0)
    }
}
