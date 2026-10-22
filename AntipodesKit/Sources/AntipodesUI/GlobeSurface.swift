import AntipodesCore
import AntipodesGlobe
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// The globe you can handle: drag to turn it, pinch to zoom, tap a pin or an arc to
/// select it, and — where the screen allows it — touch and hold to drop a pin.
///
/// Shared by the Globe tab and the globe that stands beside lists on iPad and Mac
/// (R-NAV-1), so the two turn and select the same way.
struct GlobeSurface: View {
    @Environment(GlobeBorderStore.self) private var borderStore
    @Environment(AppModel.self) private var model
    @Environment(GlobeImageryStore.self) private var imagery: GlobeImageryStore?
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverOn

    let scene: GlobeScene
    @Binding var camera: GlobeCamera
    let selection: GlobeSelection?
    var emphasised: Set<UUID> = []
    var palette = GlobePalette()
    /// Called with what a tap landed on, or `nil` for empty space.
    let onSelect: (GlobeSelection?) -> Void
    /// Touch and hold to drop a pin there (R-LOG-5). `nil` turns the gesture off.
    var onDropPin: ((Coordinate) -> Void)?

    @GestureState private var dragTranslation: CGSize = .zero
    @State private var gestureStartCamera: GlobeCamera?
    @State private var zoomStart: Double?
    @State private var pinsDropped = 0

    var body: some View {
        GeometryReader { proxy in
            GlobeCanvas(
                scene: scene,
                borders: borderStore.borders(forZoom: camera.zoom),
                camera: liveCamera(in: proxy.size),
                selection: selection,
                emphasised: emphasised,
                palette: palette,
                surface: surface,
                isInteracting: dragTranslation != .zero || zoomStart != nil
            )
            .contentShape(.rect)
            .gesture(rotation(in: proxy.size))
            .simultaneousGesture(zoom)
            .simultaneousGesture(dropPin(in: proxy.size), isEnabled: onDropPin != nil)
            .onTapGesture { location in handleTap(at: location, in: proxy.size) }
            .accessibilityValue("Facing \(camera.centre.displayText)")
            .accessibilityAdjustableAction(adjustZoom)
            .accessibilityActions { accessibilityActions }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: pinsDropped)
    }

    /// The satellite picture once it has loaded; until then, and whenever the style is
    /// standard, the vector globe.
    private var surface: GlobeSurfaceStyle {
        guard model.globeStyle == .satellite, let imagery, let image = imagery.image else {
            return .standard
        }
        return .satellite(image, imagery.rasters)
    }

    // MARK: - VoiceOver

    /// What a finger does by dragging and pinching, as actions: turn the globe a step
    /// each way, zoom by swiping up or down, and open any of the places nearest the
    /// middle of the view.
    @ViewBuilder
    private var accessibilityActions: some View {
        Button("Turn east") { turn(longitude: 30) }
        Button("Turn west") { turn(longitude: -30) }
        Button("Turn north") { turn(latitude: 20) }
        Button("Turn south") { turn(latitude: -20) }
        // Measuring every pin is wasted work on each frame of a drag unless VoiceOver
        // is there to offer them.
        if isVoiceOverOn {
            ForEach(nearestPins) { pin in
                Button("Open \(pin.place.name)") { onSelect(.pin(pin)) }
            }
        }
    }

    /// The ten places closest to where the globe is facing, on the side that shows.
    private var nearestPins: [GlobePin] {
        let quarterOfTheWorldKm = GreatCircle.earthCircumferenceKm / 4
        return scene.pins
            .filter(\.style.isTravel)
            .map { ($0, GreatCircle.distanceKm(from: camera.centre, to: $0.coordinate)) }
            .filter { $0.1 < quarterOfTheWorldKm }
            .sorted { $0.1 < $1.1 }
            .prefix(10)
            .map(\.0)
    }

    private func turn(latitude: Double = 0, longitude: Double = 0) {
        let centre = Coordinate(
            latitude: max(-80, min(80, camera.centre.latitude + latitude)),
            longitude: camera.centre.longitude + longitude
        )
        camera = GlobeCamera(centre: centre, zoom: camera.zoom)
    }

    private func adjustZoom(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment: camera = GlobeCamera(centre: camera.centre, zoom: camera.zoom * 1.5)
        case .decrement: camera = GlobeCamera(centre: camera.centre, zoom: camera.zoom / 1.5)
        @unknown default: break
        }
    }

    /// The camera including the drag in progress, so rotation tracks the finger without
    /// writing to state on every frame.
    private func liveCamera(in size: CGSize) -> GlobeCamera {
        guard dragTranslation != .zero else { return camera }
        return (gestureStartCamera ?? camera).dragged(
            dx: dragTranslation.width,
            dy: dragTranslation.height,
            in: GlobeSize(width: size.width, height: size.height)
        ).withZoom(of: camera)
    }

    private func rotation(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragTranslation) { value, state, _ in state = value.translation }
            .onChanged { _ in
                if gestureStartCamera == nil {
                    gestureStartCamera = camera
                }
            }
            .onEnded { value in
                camera = (gestureStartCamera ?? camera).dragged(
                    dx: value.translation.width,
                    dy: value.translation.height,
                    in: GlobeSize(width: size.width, height: size.height)
                ).withZoom(of: camera)
                gestureStartCamera = nil
            }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // Captured when the pinch starts, so a pinch always scales from where
                // the globe actually is.
                let base = zoomStart ?? camera.zoom
                zoomStart = base
                camera = GlobeCamera(centre: camera.centre, zoom: base * value.magnification)
            }
            .onEnded { _ in zoomStart = nil }
    }

    private func dropPin(in size: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onEnded { value in
                guard case let .second(true, drag?) = value,
                      hypot(drag.translation.width, drag.translation.height) < 12
                else { return }
                let globe = OrthographicGlobe(
                    camera: camera,
                    size: GlobeSize(width: size.width, height: size.height)
                )
                if let coordinate = globe.coordinate(at: GlobePoint(
                    x: drag.location.x,
                    y: drag.location.y
                )) {
                    pinsDropped += 1
                    onDropPin?(coordinate)
                }
            }
    }

    private func handleTap(at location: CGPoint, in size: CGSize) {
        let globe = OrthographicGlobe(
            camera: camera,
            size: GlobeSize(width: size.width, height: size.height)
        )
        onSelect(scene.selection(at: GlobePoint(x: location.x, y: location.y), globe: globe))
    }
}

/// Space behind the globe: near-black in every appearance so the arcs stay legible.
struct GlobeBackdrop: View {
    var body: some View {
        RadialGradient(
            colors: [Color(red: 0.05, green: 0.08, blue: 0.14), Palette.space],
            center: .center,
            startRadius: 40,
            endRadius: 520
        )
        .ignoresSafeArea()
    }
}

/// Whether the device has room to put things side by side.
///
/// Not the size class alone: a large iPhone in landscape reports a regular width, and
/// the iPhone keeps its own layout there (R-PLAT-1).
@MainActor
enum DeviceLayout {
    /// Whether the tab view shows as a sidebar, with room for the sidebar-only
    /// destinations. An iPhone never does, even a large one held sideways at regular
    /// width: there they would collapse into a stray "More" tab.
    @MainActor
    static func hasSidebar(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
        isSideBySide(sizeClass)
    }

    static func isSideBySide(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
        #if os(iOS)
            UIDevice.current.userInterfaceIdiom != .phone && sizeClass != .compact
        #else
            true
        #endif
    }
}

extension GlobeCamera {
    /// This camera's direction at another's zoom. A drag that a pinch interrupted keeps
    /// the pinch's zoom; rebuilding it from where the drag began would snap the zoom
    /// back to what it was before the pinch.
    func withZoom(of other: GlobeCamera) -> GlobeCamera {
        GlobeCamera(centre: centre, zoom: other.zoom)
    }
}
