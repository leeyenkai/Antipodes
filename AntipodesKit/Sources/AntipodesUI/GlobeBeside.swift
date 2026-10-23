import AntipodesCore
import AntipodesGlobe
import AntipodesStats
import SwiftUI

/// A screen's navigation stack with the globe standing beside it, where there is room
/// (R-PLAT-2, R-NAV-1).
///
/// The globe follows whatever the stack has open — a trip, a visit, a journey, a
/// country, a collection — and a tap on a pin or an arc opens that record in the stack.
/// On iPhone, and in an iPad window too narrow for two columns, it is just the stack.
///
/// On iPad it is a split view, so the system keeps the list's toolbar clear of the
/// floating tab bar and floats the list over the globe. On the Mac the stack has to be
/// the tab's own root — a stack nested in anything else hands its pushes to the window,
/// which replaces everything beside it — so there each page carries the globe beside
/// itself instead (`besideGlobe(_:)`).
struct GlobeBesideStack<Root: View>: View {
    @Environment(AppModel.self) private var model
    @State private var context = GlobeBesideContext()
    /// Whether a form open in the stack holds unsaved edits.
    @State private var hasEdits = false
    /// A widget's link that arrived over unsaved edits, held until the user decides.
    @State private var heldRoute: PendingRoute?
    private let tab: PendingRoute.Tab
    private let root: Root

    #if !os(macOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
        @State private var width: CGFloat = 0
        @State private var columns = NavigationSplitViewVisibility.all
    #endif

    init(tab: PendingRoute.Tab, @ViewBuilder root: () -> Root) {
        self.tab = tab
        self.root = root()
    }

    var body: some View {
        stack
            .onPreferenceChange(UnsavedEditsKey.self) { hasEdits = $0 }
            // A widget's link opens its record here, on top of the list itself — but not
            // over a half-edited form without asking, since it replaces the whole stack.
            .onChange(of: model.pendingRoute, initial: true) { _, pending in
                guard let pending, pending.tab == tab else { return }
                model.pendingRoute = nil
                if hasEdits {
                    heldRoute = pending
                } else {
                    open(pending)
                }
            }
            .confirmingDiscard(isPresented: Binding(
                get: { heldRoute != nil },
                set: {
                    if !$0 {
                        heldRoute = nil
                    }
                }
            )) {
                if let heldRoute {
                    open(heldRoute)
                }
                heldRoute = nil
            }
    }

    private func open(_ pending: PendingRoute) {
        var path = NavigationPath()
        path.append(pending.route)
        context.path = path
    }

    @ViewBuilder
    private var stack: some View {
        @Bindable var context = context
        #if os(macOS)
            NavigationStack(path: $context.path) { root.besideGlobe(context) }
                .environment(context)
        #else
            // The path lives in the context rather than the stack, so crossing the width
            // threshold rebuilds the stack without losing where it had navigated to.
            Group {
                if showsGlobe {
                    NavigationSplitView(columnVisibility: $columns) {
                        NavigationStack(path: $context.path) { root }
                            .navigationSplitViewColumnWidth(listWidth)
                    } detail: {
                        CompanionGlobe(focus: context.tracker.current, open: context.open)
                    }
                    .navigationSplitViewStyle(.balanced)
                } else {
                    NavigationStack(path: $context.path) { root }
                }
            }
            .environment(context)
            .environment(context.tracker)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        #endif
    }

    #if !os(macOS)
        private var showsGlobe: Bool {
            DeviceLayout.isSideBySide(sizeClass) && width >= 720
        }

        private var listWidth: CGFloat {
            GlobeBesideContext.listWidth(in: width)
        }
    #endif
}

/// The navigation behind one `GlobeBesideStack`, and what the globe beside it needs: what
/// is open, and a way to open something else.
@MainActor
@Observable
final class GlobeBesideContext {
    /// Any change the user makes — Back, or a page pushed from the list — forgets what
    /// the globe opened, so the globe's next tap never replaces the user's own page.
    var path = NavigationPath() {
        didSet {
            if !isOpening {
                depthAfterGlobeOpened = nil
            }
        }
    }

    let tracker = GlobeFocusTracker()
    /// How deep the stack was after the globe last opened something, so the next tap
    /// replaces that record instead of piling another on top of it.
    @ObservationIgnored private var depthAfterGlobeOpened: Int?
    @ObservationIgnored private var isOpening = false

    func open(_ route: LogRoute) {
        isOpening = true
        defer { isOpening = false }
        if let depth = depthAfterGlobeOpened, depth == path.count, !path.isEmpty {
            path.removeLast()
        }
        path.append(route)
        depthAfterGlobeOpened = path.count
    }

    /// About as wide as an iPhone, which is what every list here was designed at.
    static func listWidth(in width: CGFloat) -> CGFloat {
        min(440, max(380, width * 0.42))
    }
}

extension View {
    /// Makes this page one of a `GlobeBesideStack`'s: what it opens reaches the globe,
    /// and on the Mac the globe stands beside it when the window has room. With no
    /// context — a page outside such a stack — it does nothing.
    ///
    /// The context is passed in rather than read from the environment because the Mac
    /// presents pushed pages from the window's navigation, outside the stack's own
    /// environment. `LogDestinations` captures it where the destinations are declared.
    @ViewBuilder
    func besideGlobe(_ context: GlobeBesideContext?) -> some View {
        if let context {
            #if os(macOS)
                modifier(BesideGlobe(context: context))
                    .environment(context)
                    .environment(context.tracker)
            #else
                environment(context)
                    .environment(context.tracker)
            #endif
        } else {
            self
        }
    }
}

#if os(macOS)
    /// The page and the globe side by side. On iPad the split view does this instead.
    private struct BesideGlobe: ViewModifier {
        let context: GlobeBesideContext
        @State private var width: CGFloat = 0

        func body(content: Content) -> some View {
            HStack(spacing: 0) {
                content
                    .frame(width: showsGlobe ? GlobeBesideContext.listWidth(in: width) : nil)
                if showsGlobe {
                    Divider()
                    CompanionGlobe(focus: context.tracker.current, open: context.open)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }

        private var showsGlobe: Bool {
            width >= 720
        }
    }
#endif

/// What a screen beside the globe has open, so the globe can show it too.
enum GlobeFocus: Hashable {
    case trip(UUID)
    case visit(UUID)
    case journey(UUID)
    case country(String)
    case collection(String)
    case wishlist
}

extension View {
    /// Tells the globe beside this screen, if there is one, what to show while this is on
    /// screen. Does nothing on iPhone.
    func globeFocus(_ focus: GlobeFocus) -> some View {
        modifier(GlobeFocusModifier(focus: focus))
    }
}

/// The screens currently on show beside the globe, newest last.
///
/// Each registers when it appears and leaves when it disappears, so after a push or a
/// pop the last one standing is the one on top, whatever order the navigation stack
/// sends the two events in.
@MainActor
@Observable
final class GlobeFocusTracker {
    private var entries: [(token: UUID, focus: GlobeFocus)] = []

    var current: GlobeFocus? {
        entries.last?.focus
    }

    func show(_ focus: GlobeFocus, token: UUID) {
        entries.removeAll { $0.token == token }
        entries.append((token: token, focus: focus))
    }

    func hide(token: UUID) {
        entries.removeAll { $0.token == token }
    }
}

private struct GlobeFocusModifier: ViewModifier {
    @Environment(GlobeFocusTracker.self) private var tracker: GlobeFocusTracker?
    let focus: GlobeFocus
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { tracker?.show(focus, token: token) }
            .onChange(of: focus) { tracker?.show(focus, token: token) }
            .onDisappear { tracker?.hide(token: token) }
    }
}

/// The globe beside a list: the whole log, with whatever the list has open emphasised
/// and framed. A trip shows that trip alone, the way the Globe tab's trip filter does.
private struct CompanionGlobe: View {
    @Environment(AppModel.self) private var model
    let focus: GlobeFocus?
    let open: (LogRoute) -> Void

    @State private var camera = GlobeCamera.default
    @State private var scene = GlobeScene.empty
    @State private var hasFramed = false
    @State private var framedFocus: GlobeFocus?
    @State private var photoCluster: PhotoCluster?
    @State private var queuedAdd: AddRequest?

    var body: some View {
        ZStack {
            GlobeBackdrop()
            GlobeSurface(
                scene: scene,
                camera: $camera,
                selection: nil,
                emphasised: emphasised,
                onSelect: select,
                photoClusters: model.showsPhotoLayer ? model.photos.clusters : nil,
                selectedPhotoCluster: photoCluster?.id,
                onSelectPhotos: { photoCluster = $0 }
            )
            // Under the status bar and the home indicator, so a close-up fills the
            // pane, but not under the list column, so the globe centres in what shows.
            .ignoresSafeArea(edges: .vertical)
        }
        // Along the bottom rather than the top: on iPad the floating tab bar sits over
        // the top of this pane, which has no navigation bar to push content below it.
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                if !model.log.isEmpty, model.isReady {
                    GlobeSummaryBar(scene: scene)
                }
                caption
            }
            .padding(.bottom, 16)
        }
        .environment(\.colorScheme, .dark)
        .sheet(item: $photoCluster, onDismiss: openQueuedAdd) { cluster in
            PhotoClusterCard(cluster: cluster) { request in
                queuedAdd = request
                photoCluster = nil
            }
        }
        .photoLayerLoading()
        .onChange(of: Inputs(
            log: model.log,
            rules: model.rules,
            focus: focus,
            wishlist: model.openWishlistPlaces,
            wishlistRoutes: model.openWishlistRoutes,
            home: model.home,
            trackPaths: model.trackPaths
        ), initial: true) {
            rebuild()
            // Reframed when the focus moves, not on every edit: turning the globe and
            // then saving a change should leave it where the user turned it.
            if !hasFramed || framedFocus != focus {
                frame()
            }
        }
    }

    private func openQueuedAdd() {
        if let queuedAdd {
            model.addRequest = queuedAdd
            self.queuedAdd = nil
        }
    }

    private var caption: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Button("Frame", systemImage: "scope", action: frame)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .accessibilityLabel("Frame \(title)")
            GlobeStyleMenu()
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }

    private var title: String {
        switch focus {
        case nil:
            "Everywhere you've been"
        case let .trip(id):
            model.log.trip(id: id)?.displayName(model: model) ?? "Trip"
        case let .visit(id):
            model.log.visits.first { $0.id == id }?.place.name ?? "Visit"
        case let .journey(id):
            model.log.journeys.first { $0.id == id }?.displayTitle ?? "Journey"
        case let .country(code):
            model.catalogue.countries[code]?.name ?? code
        case let .collection(id):
            collection(id)?.definition.name ?? "Collection"
        case .wishlist:
            "Wishlist"
        }
    }

    // MARK: - Deriving content

    private var tripID: UUID? {
        if case let .trip(id) = focus {
            return id
        }
        return nil
    }

    private func rebuild() {
        // The same scene the Globe tab draws: legs along their railways, roads and
        // transit lines, wishlisted routes dashed.
        scene = GlobeSceneBuilder.build(
            log: model.log,
            rules: model.rules,
            filter: GlobeFilter(tripID: tripID),
            wishlist: tripID == nil ? model.openWishlistPlaces + collectionStillToVisit : [],
            wishlistRoutes: tripID == nil ? model.openWishlistRoutes : [],
            home: model.home,
            paths: model.trackPaths
        )
    }

    /// A collection's members not visited yet, drawn like wishlist places so the globe
    /// shows how much of it is left — the same points it is framed on.
    private var collectionStillToVisit: [PlaceReference] {
        guard case let .collection(id) = focus, let progress = collection(id) else { return [] }
        let wished = Set(model.openWishlistPlaces.map(\.id))
        return progress.members
            .filter { !$0.isVisited && !wished.contains($0.place.id) }
            .map(\.place)
    }

    /// The visits and legs that belong to what the list has open, by id.
    private var emphasised: Set<UUID> {
        switch focus {
        case nil, .trip, .wishlist:
            return []
        case let .visit(id):
            return [id]
        case let .journey(id):
            return Set(model.log.journeys.first { $0.id == id }?.legs.map(\.id) ?? [])
        case let .country(code):
            return Set(model.statistics.coverage.visitIDsByCountry[code] ?? [])
        case let .collection(id):
            let members = Set(collection(id)?.members.map(\.place.id) ?? [])
            return Set(scene.pins.filter { $0.style.isTravel && members.contains($0.place.id) }
                .map(\.id))
        }
    }

    /// Where to point the camera. A trip is framed on its places, as its thumbnail is:
    /// a trip to Japan is about Japan, not the flight there. A collection is framed on
    /// all its members, visited or not, so the globe shows how much of it is left.
    private var focusPoints: [Coordinate] {
        let places = scene.pins.filter(\.style.isTravel).map(\.coordinate)
        let ends = scene.arcs.flatMap { [$0.path.first, $0.path.last].compactMap(\.self) }
        switch focus {
        case nil:
            return places + ends
        case .trip:
            return places.isEmpty ? ends : places
        case .wishlist:
            return scene.pins.filter { $0.style == .wishlist }.map(\.coordinate)
        case let .collection(id):
            return collection(id)?.members.compactMap(\.place.coordinate) ?? []
        case .visit, .journey, .country:
            let ids = emphasised
            return scene.pins.filter { ids.contains($0.id) }.map(\.coordinate)
                + scene.arcs.filter { ids.contains($0.id) }
                .flatMap { [$0.path.first, $0.path.last].compactMap(\.self) }
        }
    }

    private func frame() {
        framedFocus = focus
        guard let framed = GlobeCamera.framing(focusPoints, maximumZoom: 4) else { return }
        // The first framing is instant; after that the globe turns to what was opened,
        // so the eye can follow where it went.
        if hasFramed {
            withAnimation(.easeInOut(duration: 0.6)) { camera = framed }
        } else {
            camera = framed
        }
        hasFramed = true
    }

    private func collection(_ id: String) -> CollectionProgress? {
        model.statistics.collections.first { $0.id == id }
    }

    /// A tap on a place or a journey opens it in the list beside the globe. A wishlist
    /// place is not a record yet, so a tap offers to log it; home markers stay put.
    private func select(_ selection: GlobeSelection?) {
        switch selection {
        case let .pin(pin) where pin.style.isTravel:
            open(.visit(pin.id))
        case let .pin(pin) where pin.style == .wishlist:
            model.addRequest = AddRequest(start: .place(pin.place))
        case let .arc(arc):
            if let journey = model.log.journeys
                .first(where: { $0.legs.contains { $0.id == arc.id } }) {
                open(.journey(journey.id))
            }
        case .pin, nil:
            break
        }
    }
}

/// Everything the companion's scene is derived from, so one `onChange` covers the lot.
private struct Inputs: Equatable {
    let log: TravelLog
    let rules: CountingRules
    let focus: GlobeFocus?
    let wishlist: [PlaceReference]
    let wishlistRoutes: [GlobeWishlistRoute]
    let home: PlaceReference?
    let trackPaths: [UUID: [Coordinate]]
}
