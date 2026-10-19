import AntipodesCore
import AntipodesGlobe
import SwiftUI

/// The home screen: a 3D globe of where you have been, with a timeline you can scrub
/// to replay it (§9, R-GLOBE-1 … R-GLOBE-7).
///
/// The globe is drawn from the log and from bundled vector outlines — no map tiles, no
/// network, nothing that depends on the user's own data leaving the device. That is the
/// point of it: MapKit would have fetched imagery for wherever the user's travels put
/// the camera, which is a request shaped by their private data (decision D-5, Q-3,
/// R-PRIV-7).
struct GlobeScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(GlobeBorderStore.self) private var borderStore

    @State private var camera = GlobeCamera.default
    @State private var filter = GlobeFilter.none
    @State private var scene = GlobeScene.empty
    @State private var timeline = GlobeTimeline.empty
    @State private var hasFramed = false

    /// Where the replay scrubber is parked, as an index into the timeline's stops.
    /// `nil` means the replay is off and the whole log is showing.
    @State private var replayIndex: Double?
    @State private var selection: GlobeSelection?

    @GestureState private var dragTranslation: CGSize = .zero
    @State private var gestureStartCamera: GlobeCamera?
    @State private var zoomStart: Double?

    private let palette = GlobePalette()

    var body: some View {
        NavigationStack {
            globe
                .background(backdrop)
                .overlay(alignment: .top) {
                    if !model.log.isEmpty {
                        GlobeSummaryBar(scene: scene)
                    }
                }
                .overlay(alignment: .bottom) { bottomControls }
                .overlay {
                    if model.log.isEmpty {
                        emptyPrompt
                    }
                }
                .navigationTitle("Globe")
                .toolbarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .addToolbarButton()
                .sheet(item: $selection) { GlobeSelectionSheet(selection: $0) }
            // The globe is dark whatever the appearance, so this screen's chrome
            // follows it: a dark title over a near-black sky is unreadable.
            #if os(iOS)
                .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
        }
        .environment(\.colorScheme, .dark)
        .onChange(of: GlobeInputs(
            log: model.log,
            rules: model.rules,
            filter: effectiveFilter,
            wishlist: model.openWishlistPlaces,
            home: model.home
        ), initial: true) {
            rebuild()
            if !hasFramed, !scene.isEmpty {
                hasFramed = true
                frameScene(animated: false)
            }
        }
        // Changing a filter frames what is left. Without this, filtering to one year
        // while zoomed in on the Atlantic leaves the user looking at empty ocean.
        .onChange(of: filter) { frameScene(animated: true) }
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
            .simultaneousGesture(dropPin(in: proxy.size))
            .onTapGesture { location in handleTap(at: location, in: proxy.size) }
        }
    }

    /// Space behind the globe: near-black in every appearance so the arcs stay legible.
    private var backdrop: some View {
        RadialGradient(
            colors: [Color(red: 0.05, green: 0.08, blue: 0.14), Palette.space],
            center: .center,
            startRadius: 40,
            endRadius: 520
        )
        .ignoresSafeArea()
    }

    private var emptyPrompt: some View {
        VStack(spacing: 10) {
            Text("Your travels, on a globe")
                .font(.title2.weight(.bold))
            Text(
                """
                Log a place or a journey and it appears here. Touch and hold anywhere to drop a pin.
                """
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            Button("Log Your First Place") { model.addRequest = AddRequest() }
                .buttonStyle(.glassProminent)
                .padding(.top, 6)
        }
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .padding(32)
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
                // Captured when the pinch starts, so a pinch always scales from where
                // the globe actually is.
                let base = zoomStart ?? camera.zoom
                zoomStart = base
                camera = GlobeCamera(centre: camera.centre, zoom: base * value.magnification)
            }
            .onEnded { _ in zoomStart = nil }
    }

    /// Touch and hold to drop a pin where the finger is (R-LOG-5).
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
                    model.addRequest = AddRequest(start: .pin(coordinate))
                }
            }
    }

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
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
            }
            GlobeTimelineBar(
                timeline: timeline,
                replayIndex: $replayIndex,
                onScrubToDate: focusCameraIfNeeded
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeadingCompat) {
            Button("Frame", systemImage: "scope") { frameScene(animated: true) }
                .accessibilityLabel("Frame everything")
        }
        ToolbarItem(placement: .primaryAction) {
            GlobeFilterMenu(
                filter: $filter,
                years: availableYears,
                trips: model.tripsNewestFirst,
                modes: availableModes
            )
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Drop a Pin", systemImage: "mappin.and.ellipse") {
                model.addRequest = AddRequest(start: .pin(camera.centre))
            }
        }
    }

    // MARK: - Deriving content

    /// The filter actually in force: the user's filter plus wherever the replay is.
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
            filter: effectiveFilter,
            wishlist: effectiveFilter.replayUpTo == nil ? model.openWishlistPlaces : [],
            home: model.home
        )
    }

    /// Turns the globe to the newest thing the replay has reached. The zoom is the
    /// user's, so it is left alone.
    private func focusCameraIfNeeded() {
        guard let latest = scene.pins.last(where: { $0.style.isTravel })?.coordinate
            ?? scene.arcs.last?.path.last
        else { return }
        withAnimation(.easeInOut(duration: 0.45)) {
            camera = camera.looking(at: latest)
        }
    }

    /// Points the globe at whatever the current filter left, and pulls back far enough
    /// to see it.
    private func frameScene(animated: Bool) {
        rebuild()
        let points = scene.pins.filter(\.style.isTravel).map(\.coordinate)
            + scene.arcs.flatMap { [$0.path.first, $0.path.last].compactMap(\.self) }
        guard let framed = GlobeCamera.framing(points, maximumZoom: 4) else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.6)) { camera = framed }
        } else {
            camera = framed
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
    let wishlist: [PlaceReference]
    let home: PlaceReference?
}

extension ToolbarItemPlacement {
    static var topBarLeadingCompat: ToolbarItemPlacement {
        #if os(iOS)
            .topBarLeading
        #else
            .navigation
        #endif
    }
}
