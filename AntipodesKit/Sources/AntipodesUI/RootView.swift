import AntipodesCore
import AntipodesGlobe
import Combine
import SwiftUI

/// The app's navigation shell.
///
/// Four destinations — Globe, Trips, Stats, Collections — with Settings reached from
/// Stats and Collections (§9). `.sidebarAdaptable` gives a tab bar on iPhone and a
/// sidebar on iPad and Mac from one declaration (R-PLAT-2, R-NAV-1), with the bulk
/// editing table and Settings added to the sidebar there. Where the window is wide
/// enough, the globe stays beside the lists (`GlobeBesideStack`) and opens records in an
/// inspector rather than a sheet.
///
/// Logging is reachable from anywhere in one movement: on iPhone a search-first bar
/// sits above the tab bar, within thumb reach (R-PLAT-1); with a sidebar it is a
/// toolbar button and ⌘N. On the Mac, a flight log or a backup can be dropped on the
/// window to import it (R-NAV-2).
public struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var borderStore = GlobeBorderStore()
    @State private var imagery = GlobeImageryStore()
    @State private var selection: Destination = .globe

    enum Destination: Hashable {
        case globe
        case trips
        case stats
        case collections
        case records
        case settings
    }

    public init() {}

    public var body: some View {
        @Bindable var model = model
        TabView(selection: $selection) {
            Tab("Globe", systemImage: "globe.europe.africa.fill", value: .globe) {
                GlobeScreen()
            }
            Tab("Trips", systemImage: "suitcase.fill", value: .trips) {
                TripsScreen()
            }
            Tab("Stats", systemImage: "chart.bar.xaxis", value: .stats) {
                StatsScreen()
            }
            Tab("Collections", systemImage: "square.stack.3d.up.fill", value: .collections) {
                CollectionsScreen()
            }
            // Sidebar-only destinations. On iPhone they would turn into a "More" tab,
            // so there they are reached from Trips and the Stats toolbar instead.
            if DeviceLayout.hasSidebar(sizeClass) {
                Tab("All Records", systemImage: "tablecells", value: .records) {
                    NavigationStack {
                        AllRecordsView()
                            .logDestinations()
                    }
                }
                .tabPlacement(.sidebarOnly)
                #if !os(macOS)
                    // The Mac keeps settings in their own window (⌘,), not the sidebar.
                    Tab("Settings", systemImage: "gearshape", value: .settings) {
                        SettingsScreen(isDestination: true)
                    }
                    .tabPlacement(.sidebarOnly)
                #endif
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        #if os(iOS)
            .modifier(LogAccessoryModifier(isEnabled: sizeClass == .compact && selection !=
                    .settings))
            .tabBarMinimizeBehavior(.onScrollDown)
        #endif
            // Narrowing an iPad window takes the sidebar, and with it these tabs, away;
            // a selection left on one would show an empty screen.
            .onChange(of: DeviceLayout.hasSidebar(sizeClass)) { _, hasSidebar in
                if !hasSidebar, selection == .records || selection == .settings {
                    selection = selection == .records ? .trips : .stats
                }
            }
            .overlay(alignment: .bottom) {
                UndoToast()
                    .padding(.bottom, sizeClass == .compact ? 120 : 24)
            }
            .overlay {
                if let error = model.logReadError {
                    StoreUnavailableView(error: error) { model.reload() }
                }
            }
            .focusedSceneValue(\.selectSection, SectionSelector { section in
                selection = switch section {
                case .globe: .globe
                case .trips: .trips
                case .stats: .stats
                case .collections: .collections
                }
            })
            .onOpenURL { url in
                if let link = DeepLink(url: url) {
                    open(link)
                }
            }
            .fileDropImport()
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.refreshIfDayChanged()
                }
            }
            // Posted on whatever thread noticed midnight; the model lives on the main one.
            .onReceive(
                NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
                    .receive(on: DispatchQueue.main)
            ) { _ in
                model.refreshIfDayChanged()
            }
            .environment(borderStore)
            .environment(imagery)
            .sensoryFeedback(.success, trigger: model.rideLoggedAgain)
            // The satellite picture is held only while it is the chosen style.
            .task(id: model.globeStyle) {
                if model.globeStyle == .satellite {
                    imagery.load()
                } else {
                    imagery.unload()
                }
            }
            .tint(.accentColor)
            .preferredColorScheme(model.appearance.colorScheme)
            .sheet(item: $model.addRequest) { request in
                AddSheet(request: request)
                    .environment(borderStore)
            }
            .sheet(item: $model.importRequest) { request in
                switch request {
                case .journeys: FlightImportView()
                case .photos: PhotoImportView()
                }
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: {
                        if !$0 {
                            model.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .fullScreenCoverCompat(item: onboardingBinding, onDismiss: {
                // An import chosen on onboarding's last page opens once the cover is gone.
                if let queued = model.queuedImport {
                    model.queuedImport = nil
                    model.importRequest = queued
                }
            }, content: { _ in
                OnboardingView()
                    .environment(borderStore)
            })
            .task {
                borderStore.loadCoarse()
                await model.start()
                #if DEBUG
                    await model.seedSampleDataIfRequested()
                #endif
            }
        #if os(macOS)
            // Outermost, so sheets inherit it too. On the Mac the default lays a long
            // form out in columns that do not scroll, which cut Settings off at both
            // ends; iOS forms are grouped already.
            .formStyle(.grouped)
        #endif
    }

    /// Goes where a widget's link points: a tab, or a record opened in a tab's list.
    private func open(_ link: DeepLink) {
        switch link {
        case .globe: selection = .globe
        case .trips: selection = .trips
        case .stats: selection = .stats
        case .collections: selection = .collections
        case .log: model.addRequest = AddRequest()
        case let .trip(id): show(.trip(id), in: .trips)
        case let .visit(id): show(.visit(id), in: .trips)
        case let .journey(id): show(.journey(id), in: .trips)
        case let .collection(id): show(.collection(id), in: .collections)
        }
    }

    private func show(_ route: LogRoute, in tab: PendingRoute.Tab) {
        selection = tab == .trips ? .trips : .collections
        model.pendingRoute = PendingRoute(tab: tab, route: route)
    }

    /// Onboarding shows until the user finishes it once.
    private var onboardingBinding: Binding<OnboardingItem?> {
        Binding(
            get: { model.hasCompletedOnboarding ? nil : OnboardingItem() },
            set: {
                if $0 == nil {
                    model.hasCompletedOnboarding = true
                }
            }
        )
    }
}

private struct OnboardingItem: Identifiable {
    var id: Int {
        0
    }
}

#if os(iOS)
    /// Puts the log bar above the tab bar, and takes it away where the toolbar button
    /// stands in for it. Switching it off needs iOS 26.1; on 26.0 it is always there.
    private struct LogAccessoryModifier: ViewModifier {
        let isEnabled: Bool

        func body(content: Content) -> some View {
            if #available(iOS 26.1, *) {
                content.tabViewBottomAccessory(isEnabled: isEnabled) { LogAccessory() }
            } else {
                content.tabViewBottomAccessory { LogAccessory() }
            }
        }
    }

    /// The search-first entry to logging, above the tab bar (§9, "Add").
    private struct LogAccessory: View {
        @Environment(AppModel.self) private var model
        @Environment(\.tabViewBottomAccessoryPlacement) private var placement

        var body: some View {
            Button {
                model.addRequest = AddRequest()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text(placement == .inline ? "Log" : "Log a place, flight or journey")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Palette.visited)
                }
                .padding(.horizontal, 16)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log a place or journey")
        }
    }
#endif

/// The toolbar button that opens the add sheet where there is no bottom bar: iPad in a
/// regular-width window, and the Mac, where it also answers ⌘N.
struct AddToolbarModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content.toolbar {
            if showsButton {
                ToolbarItem(placement: .primaryAction) {
                    // ⌘N belongs to the app's File menu command, which reaches this too.
                    Button("Log", systemImage: "plus") { model.addRequest = AddRequest() }
                }
            }
        }
    }

    private var showsButton: Bool {
        #if os(iOS)
            sizeClass == .regular
        #else
            true
        #endif
    }
}

extension View {
    func addToolbarButton() -> some View {
        modifier(AddToolbarModifier())
    }
}
