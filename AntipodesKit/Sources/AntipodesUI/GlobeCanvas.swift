import AntipodesCore
import AntipodesGlobe
import SwiftUI

/// What the globe's surface is drawn from.
enum GlobeSurfaceStyle {
    /// The bundled country outlines on a dark ocean.
    case standard
    /// The bundled Blue Marble picture (D-26), and the cache of globes drawn from it.
    case satellite(EquirectangularImage, GlobeRasterCache)
}

/// Draws the globe: ocean, graticule, shaded countries, journey arcs and pins.
///
/// Everything here comes from the log and from files bundled with the app — vector
/// outlines, and for the satellite style one picture of the Earth — so the screen renders
/// identically in airplane mode and makes no network request of any kind (decisions D-5
/// and D-26, R-PRIV-7). There are no map tiles and nothing to fetch.
struct GlobeCanvas: View {
    let scene: GlobeScene
    let borders: CountryBorders?
    let camera: GlobeCamera
    let selection: GlobeSelection?
    /// Pins and arcs drawn as if selected, by visit or leg id: everything belonging to
    /// what the screen beside the globe is showing (R-NAV-1).
    var emphasised: Set<UUID> = []
    let palette: GlobePalette
    var surface: GlobeSurfaceStyle = .standard
    /// While a finger is turning or pinching the globe, the satellite picture is drawn
    /// at one pixel a point to keep up, and sharpened when the globe comes to rest.
    var isInteracting = false
    /// Off the main thread on screen, so dragging stays smooth; on the main thread for
    /// `ImageRenderer`, which needs the drawing finished when it returns.
    var rendersAsynchronously = true

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: rendersAsynchronously) { context, size in
            let globe = OrthographicGlobe(
                camera: camera,
                size: GlobeSize(width: size.width, height: size.height)
            )
            draw(in: &context, globe: globe, size: size)
        }
        .drawingGroup()
        .accessibilityLabel(accessibilityLabel)
    }

    private func draw(in context: inout GraphicsContext, globe: OrthographicGlobe, size: CGSize) {
        switch surface {
        case .standard:
            drawOcean(in: &context, globe: globe)
            drawGraticule(in: &context, globe: globe)
            drawCountries(in: &context, globe: globe)
        case let .satellite(image, cache):
            drawAtmosphere(in: &context, globe: globe)
            if !drawSatellite(image, cache: cache, in: &context, globe: globe, size: size) {
                drawOcean(in: &context, globe: globe)
            }
            drawCountryOutlines(in: &context, globe: globe)
        }
        drawWishlistRoutes(in: &context, globe: globe)
        drawArcs(in: &context, globe: globe)
        drawLimbShading(in: &context, globe: globe)
        drawPins(in: &context, globe: globe)
    }

    // MARK: - The sphere

    private func disc(_ globe: OrthographicGlobe) -> Path {
        Path(
            ellipseIn: CGRect(
                x: globe.centre.x - globe.radius,
                y: globe.centre.y - globe.radius,
                width: globe.radius * 2,
                height: globe.radius * 2
            )
        )
    }

    /// A glow just outside the edge: the atmosphere, and the thing that stops the globe
    /// looking like a flat circle pasted on the background.
    private func drawAtmosphere(in context: inout GraphicsContext, globe: OrthographicGlobe) {
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: globe.radius * 0.06))
            layer.stroke(
                disc(globe),
                with: .color(palette.atmosphere),
                lineWidth: globe.radius * 0.07
            )
        }
    }

    private func drawOcean(in context: inout GraphicsContext, globe: OrthographicGlobe) {
        drawAtmosphere(in: &context, globe: globe)

        // Lit from the upper left, so the ocean reads as a curved surface.
        context.fill(
            disc(globe),
            with: .radialGradient(
                Gradient(colors: [palette.oceanHighlight, palette.ocean, palette.oceanShadow]),
                center: CGPoint(
                    x: globe.centre.x - globe.radius * 0.35,
                    y: globe.centre.y - globe.radius * 0.35
                ),
                startRadius: 0,
                endRadius: globe.radius * 1.7
            )
        )
    }

    /// Latitude and longitude lines every 30°, which give the eye the rotation.
    private func drawGraticule(in context: inout GraphicsContext, globe: OrthographicGlobe) {
        var path = Path()

        for latitude in stride(from: -60.0, through: 60.0, by: 30.0) {
            let circle = stride(from: -180.0, through: 180.0, by: 4.0).map {
                Coordinate(latitude: latitude, longitude: $0)
            }
            append(globe.clippedPolyline(circle), to: &path)
        }
        for longitude in stride(from: -180.0, to: 180.0, by: 30.0) {
            let meridian = stride(from: -90.0, through: 90.0, by: 4.0).map {
                Coordinate(latitude: $0, longitude: longitude)
            }
            append(globe.clippedPolyline(meridian), to: &path)
        }

        context.stroke(path, with: .color(palette.graticule), lineWidth: 0.5)
    }

    /// Limb darkening, drawn over the land so the whole sphere falls away at the edge
    /// rather than the continents sitting flat on top of a shaded ball.
    private func drawLimbShading(in context: inout GraphicsContext, globe: OrthographicGlobe) {
        context.fill(
            disc(globe),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.62),
                    .init(color: palette.limbShadow, location: 1),
                ]),
                center: CGPoint(
                    x: globe.centre.x - globe.radius * 0.2,
                    y: globe.centre.y - globe.radius * 0.2
                ),
                startRadius: 0,
                endRadius: globe.radius * 1.25
            )
        )
    }

    // MARK: - Land

    private func drawCountries(in context: inout GraphicsContext, globe: OrthographicGlobe) {
        guard let borders else { return }

        var land = Path()
        var visited = Path()
        var holes = Path()

        for country in borders.countries {
            guard globe.mayBeVisible(box: country.box) else { continue }
            let isVisited = country.countryCode.map(scene.shadedCountryCodes.contains) ?? false

            for ring in country.rings {
                guard globe.mayBeVisible(box: ring.box) else { continue }
                let clipped = globe.clippedRing(ring.coordinates)
                guard clipped.count > 2 else { continue }

                switch ring.role {
                case .outer:
                    appendClosed(clipped, to: &land)
                    if isVisited {
                        appendClosed(clipped, to: &visited)
                    }
                case .hole:
                    appendClosed(clipped, to: &holes)
                }
            }
        }

        // Holes are punched out of both layers at once, so a country-shaped gap does
        // not pick up the shading of the country around it.
        context.drawLayer { layer in
            layer.fill(land, with: .color(palette.land))
            layer.fill(visited, with: .color(palette.visitedLand))
            layer.blendMode = .destinationOut
            layer.fill(holes, with: .color(.black))
        }
        context.stroke(land, with: .color(palette.border), lineWidth: 0.6)
    }

    // MARK: - Satellite

    /// The Blue Marble wrapped onto the sphere. Returns false if it could not be drawn,
    /// so the plain ocean goes down instead of a hole.
    private func drawSatellite(
        _ image: EquirectangularImage,
        cache: GlobeRasterCache,
        in context: inout GraphicsContext,
        globe: OrthographicGlobe,
        size: CGSize
    ) -> Bool {
        // Two pixels a point at rest is past the picture's own detail on a phone-sized
        // globe; one a point while moving keeps a turn at the display's frame rate.
        let scale = isInteracting ? 1 : min(2, max(1, context.environment.displayScale))
        let key = GlobeRasterCache.Key(
            camera: globe.camera,
            width: size.width,
            height: size.height,
            scale: scale
        )
        let entry = cache.entry(for: key) ?? {
            guard let raster = globe.rasterise(
                image,
                viewSize: GlobeSize(width: size.width, height: size.height),
                scale: scale
            ), let picture = raster.cgImage else { return nil }
            let made = GlobeRasterCache.Entry(
                image: picture,
                frame: CGRect(
                    x: raster.originX,
                    y: raster.originY,
                    width: Double(raster.width) / scale,
                    height: Double(raster.height) / scale
                ),
                scale: scale
            )
            cache.store(made, for: key)
            return made
        }()
        guard let entry else { return false }
        context.draw(Image(decorative: entry.image, scale: entry.scale), in: entry.frame)
        return true
    }

    /// Borders over the picture: every country as a faint line, so the eye can find
    /// them, and the visited ones washed and outlined in the visited colour.
    private func drawCountryOutlines(in context: inout GraphicsContext, globe: OrthographicGlobe) {
        guard let borders else { return }
        var land = Path()
        var visited = Path()
        for country in borders.countries {
            guard globe.mayBeVisible(box: country.box) else { continue }
            let isVisited = country.countryCode.map(scene.shadedCountryCodes.contains) ?? false
            for ring in country.rings where ring.role == .outer {
                guard globe.mayBeVisible(box: ring.box) else { continue }
                let clipped = globe.clippedRing(ring.coordinates)
                guard clipped.count > 2 else { continue }
                appendClosed(clipped, to: &land)
                if isVisited {
                    appendClosed(clipped, to: &visited)
                }
            }
        }
        context.stroke(land, with: .color(palette.satelliteBorder), lineWidth: 0.5)
        context.fill(visited, with: .color(palette.visitedLand.opacity(0.28)))
        context.stroke(visited, with: .color(palette.visitedLand), lineWidth: 1.1)
    }

    // MARK: - Journeys

    /// Routes the user wants to ride, dashed in the wishlist colour like its pins.
    private func drawWishlistRoutes(in context: inout GraphicsContext, globe: OrthographicGlobe) {
        guard !scene.wishlistRoutes.isEmpty else { return }
        var path = Path()
        for route in scene.wishlistRoutes {
            append(globe.clippedPolyline(route.path), to: &path)
        }
        context.stroke(
            path,
            with: .color(palette.wishlistPin.opacity(0.85)),
            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [2, 4])
        )
    }

    private func drawArcs(in context: inout GraphicsContext, globe: OrthographicGlobe) {
        for arc in scene.arcs {
            var path = Path()
            append(globe.clippedPolyline(arc.path), to: &path)
            guard !path.isEmpty else { continue }

            let isSelected = selectedArcID == arc.id || emphasised.contains(arc.id)
            let colour = palette.colour(for: arc.mode)

            // A soft wide pass under a crisp thin one: the arcs need to read over both
            // ocean and land without a hard outline.
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: isSelected ? 4 : 2.5))
                layer.stroke(
                    path,
                    with: .color(colour.opacity(isSelected ? 0.5 : 0.3)),
                    lineWidth: isSelected ? 5 : 3
                )
            }
            // A surface leg drawn along the great circle, which is not the road or
            // track it took, is dashed: approximate, as its distance is marked
            // (R-PATH-3). One measured along the railway is drawn solid.
            context.stroke(
                path,
                with: .color(colour),
                style: StrokeStyle(
                    lineWidth: isSelected ? 2.4 : 1.3,
                    lineCap: .round,
                    dash: arc.isApproximate ? [5, 4] : []
                )
            )
        }
    }

    // MARK: - Pins

    // Every pin style is drawn in one pass over the projected points.
    // swiftlint:disable function_body_length
    private func drawPins(in context: inout GraphicsContext, globe: OrthographicGlobe) {
        for pin in scene.pins {
            let projected = globe.project(pin.coordinate)
            guard projected.isVisible else { continue }

            let isSelected = selectedPinID == pin.id || emphasised.contains(pin.id)
            let radius: Double = isSelected ? 6.5 : 4
            let centre = CGPoint(x: projected.point.x, y: projected.point.y)
            let dot = Path(
                ellipseIn: CGRect(
                    x: centre.x - radius,
                    y: centre.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )

            if isSelected {
                let halo = radius * 2.6
                context.stroke(
                    Path(ellipseIn: CGRect(
                        x: centre.x - halo,
                        y: centre.y - halo,
                        width: halo * 2,
                        height: halo * 2
                    )),
                    with: .color(palette.colour(for: pin.style).opacity(0.7)),
                    lineWidth: 1.5
                )
            }

            switch pin.style {
            case .visited:
                context.fill(dot, with: .color(palette.visitedPin))
                context.stroke(dot, with: .color(palette.pinOutline), lineWidth: 0.8)
            case .notCounted:
                // Hollow, because it is logged but not counted towards coverage: the
                // globe says the same thing the coverage number does (R-CALC-1).
                context.fill(dot, with: .color(palette.oceanShadow.opacity(0.8)))
                context.stroke(dot, with: .color(palette.notCountedPin), lineWidth: 1.4)
            case .wishlist:
                context.fill(dot, with: .color(palette.wishlistPin.opacity(0.25)))
                context.stroke(
                    dot,
                    with: .color(palette.wishlistPin),
                    style: StrokeStyle(lineWidth: 1.6, dash: [2.4, 2])
                )
            case .home:
                let ring = Path(ellipseIn: CGRect(
                    x: centre.x - 7,
                    y: centre.y - 7,
                    width: 14,
                    height: 14
                ))
                context.fill(ring, with: .color(palette.homePin))
                context.stroke(ring, with: .color(.white), lineWidth: 2)
            case .antipode:
                let ring = Path(ellipseIn: CGRect(
                    x: centre.x - 9,
                    y: centre.y - 9,
                    width: 18,
                    height: 18
                ))
                context.stroke(
                    ring,
                    with: .color(palette.homePin),
                    style: StrokeStyle(lineWidth: 2, dash: [3, 3])
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: centre.x - 2, y: centre.y - 2, width: 4, height: 4)),
                    with: .color(palette.homePin)
                )
            }
        }
    }

    // swiftlint:enable function_body_length

    // MARK: - Helpers

    private var selectedPinID: UUID? {
        if case let .pin(pin) = selection {
            return pin.id
        }
        return nil
    }

    private var selectedArcID: UUID? {
        if case let .arc(arc) = selection {
            return arc.id
        }
        return nil
    }

    private func append(_ runs: [[GlobePoint]], to path: inout Path) {
        for run in runs where run.count > 1 {
            path.move(to: CGPoint(x: run[0].x, y: run[0].y))
            for point in run.dropFirst() {
                path.addLine(to: CGPoint(x: point.x, y: point.y))
            }
        }
    }

    private func appendClosed(_ points: [GlobePoint], to path: inout Path) {
        guard let first = points.first else { return }
        path.move(to: CGPoint(x: first.x, y: first.y))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        path.closeSubpath()
    }

    private var accessibilityLabel: String {
        let countries = scene.shadedCountryCodes.count
        let places = scene.pins.filter(\.style.isTravel).count
        return "Globe showing \(places) places in \(countries) countries, "
            + "and \(scene.arcs.count) journeys."
    }
}

/// The globe's colours, kept in one place so the renderer has no literals in it.
///
/// The sphere is dark in both light and dark appearance, like a night-side globe: a
/// pale globe on a pale background loses the arcs, which are the part worth looking at.
struct GlobePalette: Sendable {
    var ocean = Color(red: 0.06, green: 0.13, blue: 0.22)
    var oceanHighlight = Color(red: 0.11, green: 0.21, blue: 0.33)
    var oceanShadow = Color(red: 0.02, green: 0.04, blue: 0.08)
    var atmosphere = Color(red: 0.45, green: 0.66, blue: 0.88).opacity(0.38)
    var limbShadow = Color.black.opacity(0.6)
    var graticule = Color.white.opacity(0.06)

    var land = Color(red: 0.20, green: 0.24, blue: 0.28)
    var visitedLand = Color(red: 0.36, green: 0.66, blue: 0.61)
    var border = Color.black.opacity(0.3)
    var satelliteBorder = Color.white.opacity(0.2)

    var visitedPin = Palette.pin
    var notCountedPin = Color.white.opacity(0.45)
    var wishlistPin = Palette.wishlist
    var homePin = Color(red: 0.80, green: 0.92, blue: 0.95)
    var pinOutline = Color.black.opacity(0.5)

    /// The same colour a mode has everywhere else in the app.
    func colour(for mode: TravelMode) -> Color {
        Palette.mode(mode)
    }

    func colour(for style: GlobePinStyle) -> Color {
        switch style {
        case .visited: visitedPin
        case .notCounted: notCountedPin
        case .wishlist: wishlistPin
        case .home, .antipode: homePin
        }
    }
}
