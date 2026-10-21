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
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var camera = GlobeCamera.default
    @State private var filter = GlobeFilter.none
    @State private var scene = GlobeScene.empty
    @State private var timeline = GlobeTimeline.empty
    @State private var hasFramed = false

    /// Where the replay scrubber is parked, as an index into the timeline's stops.
    /// `nil` means the replay is off and the whole log is showing.
    @State private var replayIndex: Double?
    @State private var selection: GlobeSelection?
    /// A tap that would replace a record with unsaved edits, held until the user says
    /// to discard them.
    @State private var pendingSelection: GlobeSelection??
    @State private var inspectorHasEdits = false
    /// An add request made from inside the selection sheet, opened once it has closed:
    /// one sheet cannot open over another that is still leaving.
    @State private var queuedAdd: AddRequest?
    @State private var sharingGlobe = false

    private let palette = GlobePalette()

    var body: some View {
        NavigationStack {
            globe
                .background(GlobeBackdrop())
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
            // The globe is dark whatever the appearance, so this screen's chrome
            // follows it: a dark title over a near-black sky is unreadable.
            #if os(iOS)
                .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
        }
        .environment(\.colorScheme, .dark)
        // Outside the dark override, so the record's form reads in the app's appearance.
        .sheet(item: sheetSelection, onDismiss: openQueuedAdd) { selection in
            GlobeSelectionSheet(selection: selection)
                .environment(\.deferredAdd, DeferredAdd { request in
                    queuedAdd = request
                    self.selection = nil
                })
        }
        .sheet(isPresented: $sharingGlobe) { ShareCardSheet(card: .globe) }
        .inspector(isPresented: isInspecting) {
            if let selection {
                GlobeSelectionInspector(selection: selection) { self.selection = nil }
                    .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
                    .onPreferenceChange(UnsavedEditsKey.self) { inspectorHasEdits = $0 }
            }
        }
        .confirmingDiscard(isPresented: isConfirmingSwitch) {
            if let pending = pendingSelection {
                selection = pending
            }
            pendingSelection = nil
        }
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
        // while zoomed in on the Atlantic leaves the user looking at empty ocean. The
        // replay starts again too: its stops belong to the old filter.
        .onChange(of: filter) {
            replayIndex = nil
            frameScene(animated: true)
        }
    }

    /// Selects what was tapped — unless the inspector holds unsaved edits to something
    /// else, in which case the user is asked first.
    private func select(_ new: GlobeSelection?) {
        if usesInspector, inspectorHasEdits, selection != nil, new?.id != selection?.id {
            pendingSelection = .some(new)
        } else {
            selection = new
        }
    }

    private var isConfirmingSwitch: Binding<Bool> {
        Binding(
            get: { pendingSelection != nil },
            set: {
                if !$0 {
                    pendingSelection = nil
                }
            }
        )
    }

    private func openQueuedAdd() {
        if let queuedAdd {
            model.addRequest = queuedAdd
            self.queuedAdd = nil
        }
    }

    // MARK: - The globe itself

    private var globe: some View {
        GlobeSurface(
            scene: scene,
            camera: $camera,
            selection: selection,
            palette: palette,
            onSelect: select,
            onDropPin: { model.addRequest = AddRequest(start: .pin($0)) }
        )
    }

    /// What was tapped opens beside the globe on iPad and Mac, so the globe stays in
    /// view while the record is edited (R-PLAT-2, R-NAV-1), and in a sheet on iPhone.
    private var usesInspector: Bool {
        DeviceLayout.isSideBySide(sizeClass)
    }

    private var sheetSelection: Binding<GlobeSelection?> {
        Binding(
            get: { usesInspector ? nil : selection },
            set: { selection = $0 }
        )
    }

    private var isInspecting: Binding<Bool> {
        Binding(
            get: { usesInspector && selection != nil },
            set: {
                if !$0 {
                    selection = nil
                }
            }
        )
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

    // MARK: - Controls

    private var bottomControls: some View {
        GlassEffectContainer(spacing: 10) {
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
        if !model.log.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button("Share", systemImage: "square.and.arrow.up") { sharingGlobe = true }
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
    ///
    /// The scene is rebuilt first: the scrubber has only just moved, and the scene still
    /// shows the stop before. The newest is by date, not by the order records were read.
    private func focusCameraIfNeeded() {
        rebuild()
        let newestPin = scene.pins.filter(\.style.isTravel).max { $0.date < $1.date }
        let newestArc = scene.arcs.max { $0.date < $1.date }
        let latest: Coordinate? = switch (newestPin, newestArc) {
        case let (pin?, arc?): arc.date > pin.date ? arc.path.last : pin.coordinate
        case let (pin?, nil): pin.coordinate
        case let (nil, arc?): arc.path.last
        case (nil, nil): nil
        }
        guard let latest else { return }
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
