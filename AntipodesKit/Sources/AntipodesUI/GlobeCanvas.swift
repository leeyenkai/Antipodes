import AntipodesCore
import AntipodesGlobe
import SwiftUI

/// Draws the globe: ocean, graticule, shaded countries, journey arcs and pins.
///
/// Everything here comes from the log and from bundled vector outlines, so the screen
/// renders identically in airplane mode and makes no network request of any kind
/// (decision D-5, R-PRIV-7). There is no map imagery and nothing to fetch.
struct GlobeCanvas: View {
    let scene: GlobeScene
    let borders: CountryBorders?
    let camera: GlobeCamera
    let selection: GlobeSelection?
    let palette: GlobePalette
    /// Off the main thread on screen, so dragging stays smooth; on the main thread for
    /// `ImageRenderer`, which needs the drawing finished when it returns.
    var rendersAsynchronously = true

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: rendersAsynchronously) { context, size in
            let globe = OrthographicGlobe(
                camera: camera,
                size: GlobeSize(width: size.width, height: size.height)
            )
            draw(in: &context, globe: globe)
        }
        .drawingGroup()
        .accessibilityLabel(accessibilityLabel)
    }

    private func draw(in context: inout GraphicsContext, globe: OrthographicGlobe) {
        drawOcean(in: &context, globe: globe)
        drawGraticule(in: &context, globe: globe)
        drawCountries(in: &context, globe: globe)
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

    private func drawOcean(in context: inout GraphicsContext, globe: OrthographicGlobe) {
        let sphere = disc(globe)

        // A glow just outside the edge: the atmosphere, and the thing that stops the
        // globe looking like a flat circle pasted on the background.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: globe.radius * 0.06))
            layer.stroke(
                sphere,
                with: .color(palette.atmosphere),
                lineWidth: globe.radius * 0.07
            )
        }

        // Lit from the upper left, so the ocean reads as a curved surface.
        context.fill(
            sphere,
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

    // MARK: - Journeys

    private func drawArcs(in context: inout GraphicsContext, globe: OrthographicGlobe) {
        for arc in scene.arcs {
            var path = Path()
            append(globe.clippedPolyline(arc.path), to: &path)
            guard !path.isEmpty else { continue }

            let isSelected = selectedArcID == arc.id
            let colour = palette.colour(for: arc.mode)

            // A soft wide pass under a crisp thin one: the arcs need to read over both
            // ocean and land without a hard outline.
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: isSelected ? 5 : 3))
                layer.stroke(
                    path,
                    with: .color(colour.opacity(0.55)),
                    lineWidth: isSelected ? 6 : 3.5
                )
            }
            context.stroke(
                path,
                with: .color(colour),
                style: StrokeStyle(lineWidth: isSelected ? 2.6 : 1.5, lineCap: .round)
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

            let isSelected = selectedPinID == pin.id
            let radius: Double = isSelected ? 7 : 4.5
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
                context.stroke(dot, with: .color(palette.pinOutline), lineWidth: 1)
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
    var ocean = Color(red: 0.07, green: 0.16, blue: 0.29)
    var oceanHighlight = Color(red: 0.14, green: 0.28, blue: 0.46)
    var oceanShadow = Color(red: 0.02, green: 0.05, blue: 0.11)
    var atmosphere = Color(red: 0.36, green: 0.62, blue: 0.95).opacity(0.5)
    var limbShadow = Color.black.opacity(0.65)
    var graticule = Color.white.opacity(0.08)

    var land = Color(red: 0.24, green: 0.29, blue: 0.35)
    var visitedLand = Color(red: 0.31, green: 0.74, blue: 0.59)
    var border = Color.black.opacity(0.35)

    var visitedPin = Color(red: 0.99, green: 0.85, blue: 0.42)
    var notCountedPin = Color.white.opacity(0.45)
    var wishlistPin = Color(red: 0.78, green: 0.62, blue: 0.98)
    var homePin = Color(red: 0.36, green: 0.86, blue: 0.96)
    var pinOutline = Color.black.opacity(0.55)

    func colour(for mode: TravelMode) -> Color {
        switch mode {
        case .flight: Color(red: 1.0, green: 0.58, blue: 0.24)
        case .rail: Color(red: 0.42, green: 0.80, blue: 0.98)
        case .cityTransit: Color(red: 0.60, green: 0.86, blue: 0.70)
        case .coach: Color(red: 0.96, green: 0.76, blue: 0.40)
        case .ferry: Color(red: 0.48, green: 0.68, blue: 1.0)
        case .roadTrip: Color(red: 0.98, green: 0.62, blue: 0.62)
        case .humanPowered: Color(red: 0.74, green: 0.92, blue: 0.52)
        case .cableAndMountain: Color(red: 0.86, green: 0.72, blue: 0.98)
        }
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
