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
        GlobeBesideStack {
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
                    Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
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
                ProgressRing(progress: progress.fraction, lineWidth: 7)
                Image(systemName: progress.definition.symbol ?? "square.stack.3d.up")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(progress.isComplete ? Palette.visited : .primary)
            }
            .frame(width: 62, height: 62)
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
                }
            }
            .navigationTitle(progress.definition.name)
            .toolbarTitleDisplayMode(.inline)
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
            Image(systemName: member.isVisited ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(member.isVisited ? Palette.visited : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.place.name)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !member.isVisited {
                Button {
                    toggleWishlist()
                } label: {
                    Image(systemName: member.isWishlisted ? "star.fill" : "star")
                        .foregroundStyle(member.isWishlisted ? Palette.wishlist : .secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(member
                    .isWishlisted ? "Remove from wishlist" : "Add to wishlist")
            }
        }
        .contextMenu {
            if member.place.kind != .route {
                Button("Log a Visit", systemImage: "plus") {
                    model.addRequest = AddRequest(start: .place(member.place))
                }
            } else if let route = routeInfo {
                Button("Log This Ride", systemImage: "plus") {
                    model.addRequest = AddRequest(start: .route(route))
                }
            }
        }
        .accessibilityElement(children: .combine)
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

private struct AchievementsGrid: View {
    @Environment(AppModel.self) private var model
    @State private var selected: AchievementStatus?

    var body: some View {
        let achievements = model.statistics.achievements
        let earned = achievements.filter(\.isEarned).count
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("\(earned) of \(achievements.count) earned")
                        .font(.headline)
                    Spacer()
                    ProgressRing(progress: achievements
                        .isEmpty ? 0 : Double(earned) / Double(achievements.count))
                        .frame(width: 28, height: 28)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 14)], spacing: 18) {
                    ForEach(achievements) { status in
                        Button {
                            selected = status
                        } label: {
                            AchievementBadge(status: status)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .sheet(item: $selected) { status in
            AchievementDetail(status: status)
        }
    }
}

struct AchievementBadge: View {
    let status: AchievementStatus
    var size: CGFloat = 76

    var body: some View {
        let tint = Palette.tier(status.definition.tier)
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(status
                        .isEarned ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(.quaternary))
                ProgressRing(progress: status.progress, tint: tint, lineWidth: 4)
                    .padding(-6)
                    .opacity(status.isEarned ? 0 : 1)
                Image(systemName: status.definition.symbol ?? "star.fill")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(status.isEarned ? .white : .secondary)
            }
            .frame(width: size, height: size)
            .shadow(color: status.isEarned ? tint.opacity(0.5) : .clear, radius: 8)
            Text(status.definition.name)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(status.isEarned ? .primary : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(status
            .isEarned ? "Earned" : "\(Format.percent(status.progress, digits: 0)) complete")
    }
}

private struct AchievementDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let status: AchievementStatus

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                AchievementBadge(status: status, size: 120)
                    .padding(.top, 20)
                Text(status.definition.description)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                if let tier = status.definition.tier {
                    Text(tier.displayName.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(Palette.tier(tier))
                }
                Text(progressText)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(status.isEarned ? Palette.visited : .secondary)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .navigationTitle(status.definition.name)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var progressText: String {
        if status.isEarned {
            return status.earnedOn.map { "Earned \(Format.day($0))" } ?? "Earned"
        }
        let system = model.rules.unitSystem
        switch status.measure {
        case .count:
            return "\(Int(status.current)) of \(Int(status.target))"
        case .kilometres:
            let current = Format.distance(status.current, system)
            return "\(current) of \(Format.distance(status.target, system))"
        case .antipodalGapKilometres:
            guard status.current.isFinite else { return "Log places on both sides of the world" }
            return "Closest so far: \(Format.distance(status.current, system)) from antipodal"
        case .yesNo:
            return "Not yet"
        }
    }
}

// MARK: - Wishlist

private struct WishlistView: View {
    @Environment(AppModel.self) private var model
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
                Button("Add to Wishlist", systemImage: "plus") { isAdding = true }
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
        if status.item.routeID != nil {
            return "Route"
        }
        return status.item.place?.contextLine ?? ""
    }

    private func log() {
        if let routeID = status.item.routeID, let route = model.route(id: routeID) {
            model.addRequest = AddRequest(start: .route(route))
        } else if let place = status.item.place {
            model.addRequest = AddRequest(start: .place(place))
        }
    }
}
