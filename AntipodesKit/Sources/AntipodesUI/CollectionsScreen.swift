import AntipodesCore
import AntipodesStats
import SwiftUI

/// Achievements, the wishlist and curated collections (§8, §9).
struct CollectionsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var section: Section = .collections
    @State private var isShowingSettings = false

    enum Section: String, CaseIterable, Identifiable {
        case collections
        case achievements
        case wishlist

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .collections: "Collections"
            case .achievements: "Badges"
            case .wishlist: "Wishlist"
            }
        }
    }

    var body: some View {
        GlobeBesideStack(tab: .collections) {
            Group {
                switch section {
                case .collections: CollectionsList()
                case .achievements: AchievementsGrid()
                case .wishlist: WishlistView()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle(section.title)
            .addToolbarButton()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    #if os(macOS)
                        // The Mac keeps settings in their own window (⌘,).
                        SettingsLink {
                            Label("Settings", systemImage: "gearshape")
                        }
                    #else
                        Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                    #endif
                }
            }
            .logDestinations()
            .sheet(isPresented: $isShowingSettings) {
                SettingsScreen()
            }
        }
    }
}

// MARK: - Collections

private struct CollectionsList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let collections = model.statistics.collections
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                ForEach(collections) { progress in
                    NavigationLink(value: LogRoute.collection(progress.id)) {
                        CollectionCard(progress: progress)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            if collections.isEmpty {
                ContentUnavailableView(
                    "No collections",
                    systemImage: "square.stack.3d.up",
                    description: Text("Collections arrive with the place database.")
                )
            }
        }
    }
}

private struct CollectionCard: View {
    let progress: CollectionProgress

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                ProgressRing(progress: progress.fraction, lineWidth: 3)
                Image(systemName: progress.definition.symbol ?? "square.stack.3d.up")
                    .font(.title3.weight(.light))
                    .foregroundStyle(progress.isComplete ? Palette.visited : .primary)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(progress.definition.name)
                    .font(.headline)
                Text("\(progress.visitedCount) of \(progress.total) visited")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(progress.isComplete ? Palette.visited : .secondary)
                if let description = progress.definition.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// One collection: every member, ticked off or not, and a way to wishlist the rest
/// (R-WISH-2, R-WISH-3).
struct CollectionDetailView: View {
    @Environment(AppModel.self) private var model
    let collectionID: String
    @State private var showsRemainingOnly = false

    var body: some View {
        if let progress = model.statistics.collections.first(where: { $0.id == collectionID }) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(progress.visitedCount)")
                                .font(.statValue(44))
                            Text("of \(progress.total)")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Format.percent(progress.fraction, digits: 0))
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Palette.visited)
                        }
                        ProgressView(value: progress.fraction)
                            .tint(Palette.visited)
                        if let description = progress.definition.description {
                            Text(description).foregroundStyle(.secondary)
                        }
                        if let completed = progress.completedOn {
                            Label(
                                "Completed \(Format.day(completed))",
                                systemImage: "checkmark.seal.fill"
                            )
                            .foregroundStyle(Palette.visited)
                        }
                    }
                    .padding(.vertical, 4)
                    Toggle("Show only what's left", isOn: $showsRemainingOnly)
                }
                Section {
                    ForEach(progress.members
                        .filter { !showsRemainingOnly || !$0.isVisited }) { member in
                            MemberRow(member: member)
                        }
                    if showsRemainingOnly, progress.isComplete {
                        Label("Every one ticked off.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Palette.visited)
                    }
                }
            }
            .navigationTitle(progress.definition.name)
            .toolbarTitleDisplayMode(.inline)
            .shareCardButton { .collection(collectionID) }
            .globeFocus(.collection(collectionID))
        } else {
            ContentUnavailableView(
                "Collection not found",
                systemImage: "questionmark.square.dashed"
            )
        }
    }
}

private struct MemberRow: View {
    @Environment(AppModel.self) private var model
    let member: CollectionMemberStatus

    var body: some View {
        HStack(spacing: 12) {
            // Still to do: a tap logs it. Done: there is nothing more to do here.
            Button(action: log) {
                HStack(spacing: 12) {
                    Image(systemName: member.isVisited ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(member.isVisited ? Palette.visited : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.place.name)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(member.isVisited)
            .accessibilityElement(children: .combine)
            .accessibilityHint(member.isVisited ? "" : "Logs it")
            if !member.isVisited {
                Button {
                    toggleWishlist()
                } label: {
                    Image(systemName: member.isWishlisted ? "star.fill" : "star")
                        .foregroundStyle(member.isWishlisted ? Palette.wishlist : .secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(member
                    .isWishlisted ? "Remove from Wishlist" : "Add to Wishlist")
            }
        }
        .contextMenu {
            if member.place.kind != .route {
                Button("Log a Visit", systemImage: "plus", action: log)
            } else if routeInfo != nil {
                Button("Log This Ride", systemImage: "plus", action: log)
            }
        }
    }

    private func log() {
        if let route = routeInfo {
            model.addRequest = AddRequest(start: .route(route))
        } else if member.place.kind != .route {
            model.addRequest = AddRequest(start: .place(member.place))
        }
    }

    private var subtitle: String {
        if let day = member.firstVisited {
            return "Visited \(Format.day(day))"
        }
        if member.isVisited {
            return "Visited"
        }
        return member.place.contextLine
    }

    private var routeInfo: RouteInfo? {
        if case let .database(.route, row) = member.place.id {
            return model.route(id: row)
        }
        return nil
    }

    private func toggleWishlist() {
        if let route = routeInfo {
            if member.isWishlisted {
                model
                    .removeFromWishlist(model.log.wishlist.filter { $0.routeID == route.id }
                        .map(\.id))
            } else {
                model.addToWishlist(route: route)
            }
        } else if member.isWishlisted {
            model.removeFromWishlist(place: member.place)
        } else {
            model.addToWishlist(member.place)
        }
    }
}

// MARK: - Achievements

private struct WishlistView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isAdding = false

    var body: some View {
        let statuses = model.statistics.wishlist
        List {
            if statuses.isEmpty {
                EmptyStateView(
                    title: "Your wishlist is empty",
                    message: """
                    Save places you want to go. They show on the globe, and tick themselves off \
                    when you log a visit.
                    """,
                    systemImage: "star",
                    actionTitle: "Add a Place",
                    action: { isAdding = true }
                )
                .listRowBackground(Color.clear)
            }
            let open = statuses.filter { !$0.isVisited }
            let done = statuses.filter(\.isVisited)
            if !open.isEmpty {
                Section("To visit") {
                    ForEach(open) { status in
                        WishlistRow(status: status)
                    }
                    .onDelete { offsets in
                        model.removeFromWishlist(offsets.map { open[$0].id })
                    }
                }
            }
            if !done.isEmpty {
                Section("Been there") {
                    ForEach(done) { status in
                        WishlistRow(status: status)
                    }
                    .onDelete { offsets in
                        model.removeFromWishlist(offsets.map { done[$0].id })
                    }
                }
            }
        }
        .globeFocus(.wishlist)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(
                    "Add to Wishlist",
                    systemImage: DeviceLayout.hasSidebar(sizeClass) ? "star.circle" : "plus"
                ) { isAdding = true }
            }
        }
        .sheet(isPresented: $isAdding) {
            PlacePickerSheet(
                title: "Add to Wishlist",
                prompt: "Places and routes",
                kinds: [.country, .city, .landmark, .route]
            ) { place in
                if case let .database(.route, row) = place.id, let route = model.route(id: row) {
                    model.addToWishlist(route: route)
                } else {
                    model.addToWishlist(place)
                }
            }
        }
    }
}

private struct WishlistRow: View {
    @Environment(AppModel.self) private var model
    let status: WishlistStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.isVisited ? "checkmark.circle.fill" : "star.fill")
                .foregroundStyle(status.isVisited ? Palette.visited : Palette.wishlist)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.item.title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !status.isVisited {
                Button("Log", systemImage: "plus.circle") { log() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.title3)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if status.isVisited {
            return status.firstVisited.map { "Visited \(Format.day($0))" } ?? "Visited"
        }
        if status.item.isRoute {
            return "Route"
        }
        return status.item.wishedPlace?.contextLine ?? ""
    }

    private func log() {
        if let routeID = status.item.routeID, let route = model.route(id: routeID) {
            model.addRequest = AddRequest(start: .route(route))
        } else if let place = status.item.wishedPlace {
            model.addRequest = AddRequest(start: .place(place))
        }
    }
}
