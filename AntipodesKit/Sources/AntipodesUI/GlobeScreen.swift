import AntipodesCore
import AntipodesGlobe
import SwiftUI

/// The home screen: a 3D globe of where you have been, with a timeline you can scrub
/// to replay it (§9, R-GLOBE-1 … R-GLOBE-5).
///
/// The globe is drawn from the log and from bundled vector outlines — no map tiles, no
/// network, nothing that depends on the user's own data leaving the device. That is the
/// point of it: MapKit would have fetched imagery for wherever the user's travels put
/// the camera, which is a request shaped by their private data (decision D-5, Q-3,
/// R-PRIV-7).
struct GlobeScreen: View {
    @Environment(AppModel.self) private var model

    @State private var borderStore = GlobeBorderStore()
    @State private var camera = GlobeCamera.default
    @State private var filter = GlobeFilter.none
    @State private var scene = GlobeScene.empty
    @State private var timeline = GlobeTimeline.empty

    /// Where the replay scrubber is parked, as an index into the timeline's stops.
    /// `nil` means the replay is off and the whole log is showing.
    @State private var replayIndex: Double?
    @State private var selection: GlobeSelection?

    @GestureState private var dragTranslation: CGSize = .zero
    @State private var gestureStartCamera: GlobeCamera?
    @State private var canvasSize = GlobeSize(width: 0, height: 0)

    private let palette = GlobePalette()

    var body: some View {
        NavigationStack {
            globe
                .background(backdrop)
                .overlay(alignment: .top) { GlobeSummaryBar(scene: scene, model: model) }
                .overlay(alignment: .bottom) { bottomControls }
                .navigationTitle("Globe")
                .toolbarTitleDisplayMode(.inline)
                .toolbar { filterMenu }
                .sheet(item: $selection) { GlobeSelectionSheet(selection: $0) }
            // The globe is dark whatever the system appearance is, so this screen's
            // own chrome follows it rather than the system: a dark navigation title
            // over a near-black sky is unreadable. The rest of the app is unaffected.
            #if os(iOS)
                .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
        }
        .environment(\.colorScheme, .dark)
        .onAppear { borderStore.loadCoarse() }
        .onChange(
            of: GlobeInputs(log: model.log, rules: model.rules, filter: effectiveFilter),
            initial: true
        ) {
            rebuild()
        }
        // Changing a filter frames what is left. Without this, filtering to one year
        // while zoomed in on the Atlantic leaves the user looking at empty ocean and
        // wondering whether the filter did anything.
        .onChange(of: filter) { frameScene() }
    }

    // MARK: - The globe itself

    private var globe: some View {
        GeometryReader { proxy in
            GlobeCanvas(
                scene: scene,
                borders: borderStore.borders(forZoom: camera.zoom),
                camera: liveCamera(in: proxy.size),
                selection: selection,
                palette: palette
            )
            .contentShape(.rect)
            .gesture(rotation(in: proxy.size))
            .simultaneousGesture(zoom)
            .onTapGesture { location in handleTap(at: location, in: proxy.size) }
            .onChange(of: proxy.size, initial: true) { _, size in
                canvasSize = GlobeSize(width: size.width, height: size.height)
            }
        }
    }

    /// Space behind the globe. Kept near-black in both appearances so the arcs stay
    /// legible; the rest of the app's chrome follows the system as usual.
    private var backdrop: some View {
        LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.04, blue: 0.08),
                Color(red: 0.01, green: 0.01, blue: 0.03),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    /// The camera including the drag in progress, so rotation tracks the finger without
    /// writing to state on every frame.
    private func liveCamera(in size: CGSize) -> GlobeCamera {
        guard dragTranslation != .zero else { return camera }
        return (gestureStartCamera ?? camera).dragged(
            dx: dragTranslation.width,
            dy: dragTranslation.height,
            in: GlobeSize(width: size.width, height: size.height)
        )
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
                )
                gestureStartCamera = nil
            }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // Captured when the pinch starts rather than kept between gestures, so
                // a pinch always scales from where the globe actually is. Holding it in
                // a running variable made the first pinch after a filter change jump.
                let base = zoomStart ?? camera.zoom
                zoomStart = base
                camera = GlobeCamera(centre: camera.centre, zoom: base * value.magnification)
            }
            .onEnded { _ in zoomStart = nil }
    }

    @State private var zoomStart: Double?

    private func handleTap(at location: CGPoint, in size: CGSize) {
        let globe = OrthographicGlobe(
            camera: camera,
            size: GlobeSize(width: size.width, height: size.height)
        )
        selection = scene.selection(
            at: GlobePoint(x: location.x, y: location.y),
            globe: globe
        )
    }

    // MARK: - Controls

    private var bottomControls: some View {
        VStack(spacing: 10) {
            if let message = borderStore.failure {
                CaveatLabel(text: message)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: .rect(cornerRadius: 10))
            }
            GlobeTimelineBar(
                timeline: timeline,
                replayIndex: $replayIndex,
                onScrubToDate: focusCameraIfNeeded
            )
        }
        .padding(.horizontal, 16)
        // Clears the floating add button, which sits 72 points up and is 56 tall.
        .padding(.bottom, 140)
    }

    @ToolbarContentBuilder
    private var filterMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            GlobeFilterMenu(
                filter: $filter,
                years: availableYears,
                trips: model.log.trips,
                modes: availableModes
            )
        }
    }

    // MARK: - Deriving content

    /// The filter actually in force, which is the user's filter plus wherever the
    /// replay scrubber is.
    private var effectiveFilter: GlobeFilter {
        var combined = filter
        if let replayIndex {
            combined.replayUpTo = timeline.date(atIndex: Int(replayIndex.rounded()))
        }
        return combined
    }

    private func rebuild() {
        // The timeline is built from the user's filter but not from the replay
        // position, or scrubbing would shorten the thing being scrubbed.
        timeline = GlobeTimeline(log: model.log, rules: model.rules, filter: filter)
        scene = GlobeSceneBuilder.build(
            log: model.log,
            rules: model.rules,
            filter: effectiveFilter
            // Wishlist pins are a [V1] feature (§8). The seam is here: pass the
            // wishlist in and the builder styles it separately.
        )
    }

    /// Turns the globe to the newest thing the replay has reached, so scrubbing
    /// actually shows the travel rather than leaving it round the back. The zoom is
    /// left alone: the user set that.
    private func focusCameraIfNeeded() {
        guard let latest = scene.pins.last?.coordinate ?? scene.arcs.last?.path.last else { return }
        withAnimation(.easeInOut(duration: 0.45)) {
            camera = camera.looking(at: latest)
        }
    }

    /// Points the globe at whatever the current filter left, and pulls back far enough
    /// to see it.
    private func frameScene() {
        rebuild()
        guard let focus = scene.focusCoordinate else { return }
        withAnimation(.easeInOut(duration: 0.5)) {
            camera = GlobeCamera(centre: focus, zoom: 1)
        }
    }

    private var availableYears: [Int] {
        Set(model.log.visits.compactMap(\.date.year))
            .union(model.log.allLegs.compactMap(\.date.year))
            .sorted(by: >)
    }

    private var availableModes: [TravelMode] {
        TravelMode.allCases.filter { mode in model.log.allLegs.contains { $0.mode == mode } }
    }
}

/// Everything the scene is derived from, so one `onChange` covers the lot.
private struct GlobeInputs: Equatable {
    let log: TravelLog
    let rules: CountingRules
    let filter: GlobeFilter
}
