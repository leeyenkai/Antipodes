import AntipodesCore
import AntipodesStats
import Charts
import SwiftUI

/// Drill-downs from a number to what it rests on (§7: every number is tappable).
enum StatsRoute: Hashable {
    case countries
    case places(PlaceKind)
    case capitals
    case unesco
    case personality
    case legs(TravelMode?)
    case legFilter(LegFilter)
    case carbon(TravelMode?)
    case ranked(RankedList)
    case grouped(GroupedList)
    case operators
    case timeByMode
    case temperatures
    case transitSystems
    case transitSystem(Int64)
    case repeats
    case gaps
    case continents
    case trips
    /// Any set of visits, under a title: a place's visits, a month's.
    case visits(title: String, ids: [UUID])
}

/// The stats dashboard (§9): personality first, then the five families.
///
/// Every figure carries its caveat, so the user can see what it rests on (R-CALC-5).
struct StatsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var sharing: ShareItem?
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if model.statsFilter.isActive {
                        StatsFilterBanner()
                    }
                    if model.log.isEmpty {
                        EmptyStateView(
                            title: "No stats yet",
                            message: "Log a place or a journey and your numbers start here.",
                            systemImage: "chart.bar.xaxis",
                            actionTitle: "Log a Place",
                            action: { model.addRequest = AddRequest() }
                        )
                    } else if model.statsFilter.isActive, model.shownLog.isEmpty {
                        ContentUnavailableView(
                            "Nothing in this slice",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("No visits or journeys match the filter.")
                        )
                    } else {
                        PersonalityHero()
                        HeadlineGrid()
                        CoverageSection()
                        DistanceSection()
                        JourneyDetailSection()
                        TransitSection()
                        CarbonSection()
                        AttributesSection()
                        PatternsSection()
                        ThemesSection()
                        YearInReviewTeaser()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(.background)
            .navigationTitle("Stats")
            .addToolbarButton()
            .toolbar {
                if !model.log.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        StatsFilterMenu()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Share Globe", systemImage: "square.and.arrow.up") {
                        sharing = ShareItem(card: .globe)
                    }
                }
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
            .navigationDestination(for: StatsRoute.self) { route in
                StatsDrillDown(route: route)
            }
            .environment(\.shareStat, ShareAction { sharing = ShareItem(card: $0) })
            .sheet(item: $sharing) { item in
                ShareCardSheet(card: item.card)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsScreen()
            }
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let card: ShareCard
}

/// A titled group of stats.
struct StatsSection<Content: View>: View {
    let title: String
    let symbol: String
    var caveat: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title3.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .padding(.leading, 4)
            content
            if let caveat {
                CaveatLabel(text: caveat)
            }
        }
    }
}

/// One labelled figure in a stats card, optionally opening what it rests on.
struct StatRow<Destination: Hashable>: View {
    let title: String
    let value: String
    var symbol: String?
    var detail: String?
    var destination: Destination?
    @Environment(\.shareStat) private var shareStat

    var body: some View {
        if let destination {
            NavigationLink(value: destination) { row(chevron: true) }
                .buttonStyle(.plain)
        } else {
            row(chevron: false)
        }
    }

    private func row(chevron: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.body.weight(.medium).monospacedDigit())
                .multilineTextAlignment(.trailing)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 9)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .contextMenu {
            if let shareStat {
                Button("Share…", systemImage: "square.and.arrow.up") {
                    shareStat(.stat(
                        title: title.lowercased(),
                        value: value,
                        detail: detail?.components(separatedBy: "\n").first,
                        symbol: symbol ?? "chart.bar.fill"
                    ))
                }
            }
        }
    }
}

extension StatRow where Destination == StatsRoute {
    init(
        _ title: String,
        _ value: String,
        symbol: String? = nil,
        detail: String? = nil,
        route: StatsRoute? = nil
    ) {
        self.title = title
        self.value = value
        self.symbol = symbol
        self.detail = detail
        destination = route
    }
}

/// Rows inside one card, separated by hairlines.
struct StatCardList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                    subview
                    if index < subviews.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(.background.secondary, in: .rect(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Hero and headlines

private struct PersonalityHero: View {
    @Environment(AppModel.self) private var model

    @Environment(\.shareStat) private var shareStat

    var body: some View {
        NavigationLink(value: StatsRoute.personality) {
            content
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let shareStat, model.shownStatistics.themes.personality != nil {
                Button("Share…", systemImage: "square.and.arrow.up") { shareStat(.personality) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let themes = model.shownStatistics.themes
        if let personality = themes.personality {
            let tint = Palette.archetype(personality.archetype)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow("Your travel personality")
                        Text(personality.archetype.name)
                            .font(.display(.largeTitle))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: personality.archetype.symbolName)
                        .font(.title2.weight(.light))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
                Text(personality.archetype.summary)
                    .foregroundStyle(.secondary)
                ThemeBars(shares: Array(themes.shares.prefix(4)), tint: tint)
                Text(
                    """
                    From \(Format.ordinalCount(personality.landmarkCount, "landmark")) you've \
                    visited. Tap to see why.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .card(padding: 20)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Travel personality", systemImage: "sparkles")
                    .font(.headline)
                let needed = TravelPersonality.minimumLandmarks - themes.landmarkCount
                Text("""
                Log \(Format.ordinalCount(
                    max(1, needed),
                    "more landmark"
                )) — a museum, a temple, a \
                national park — and Antipodes reads your travel personality from what you \
                chose to see.
                """)
                .foregroundStyle(.secondary)
            }
            .card(padding: 20)
        }
    }
}

struct ThemeBars: View {
    let shares: [ThemeShare]
    var tint: Color = Palette.visited
    // Sized with the text, so a large text size widens the columns instead of
    // truncating every label.
    @ScaledMetric(relativeTo: .subheadline) private var labelWidth: CGFloat = 130
    @ScaledMetric(relativeTo: .caption) private var percentWidth: CGFloat = 38

    var body: some View {
        VStack(spacing: 8) {
            ForEach(shares) { share in
                HStack(spacing: 10) {
                    Text(share.label)
                        .font(.subheadline)
                        .frame(width: labelWidth, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(tint.opacity(0.14))
                            Capsule()
                                .fill(tint)
                                .frame(width: max(
                                    4,
                                    proxy.size.width * share.share / max(
                                        0.001,
                                        shares.first?.share ?? 1
                                    )
                                ))
                        }
                    }
                    .frame(height: 4)
                    Text(Format.percent(share.share, digits: 0))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: percentWidth, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct HeadlineGrid: View {
    @Environment(AppModel.self) private var model
    /// "24.4% of 193", or a plain warning when the list it measures against could not
    /// be read and every visited code had to be counted.
    private func worldShare(_ coverage: CoverageStatistics) -> String {
        let share = Format.percent(coverage.worldFraction)
        return coverage.isCountryListAvailable
            ? "\(share) of \(coverage.worldCountryCount)"
            : "About \(share) — country list unavailable"
    }

    var body: some View {
        let statistics = model.shownStatistics
        let coverage = statistics.coverage
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            NavigationLink(value: StatsRoute.countries) {
                StatCard(
                    title: "Countries",
                    value: "\(coverage.listedCountriesVisited)",
                    detail: worldShare(coverage),
                    symbol: "flag.fill",
                    shareTitle: "countries visited"
                )
            }
            NavigationLink(value: StatsRoute.legs(nil)) {
                StatCard(
                    title: "Distance",
                    value: Format.distance(statistics.distance.totalKm, model.rules.unitSystem),
                    detail: """
                    \(Format.multiple(statistics.distance.timesRoundTheEarth)) round the Earth
                    """,
                    symbol: "point.topleft.down.to.point.bottomright.curvepath",
                    shareTitle: "travelled"
                )
            }
            NavigationLink(value: StatsRoute.continents) {
                StatCard(
                    title: "Continents",
                    value: "\(coverage.continentsVisited) of 7",
                    detail: coverage.continents.sorted().map(\.displayName).joined(separator: ", "),
                    symbol: "globe.americas.fill"
                )
            }
            NavigationLink(value: StatsRoute.places(.city)) {
                StatCard(
                    title: "Cities",
                    value: "\(coverage.citiesVisited)",
                    detail: "\(coverage.capitalsVisited) capitals",
                    symbol: "building.2.fill"
                )
            }
        }
        .buttonStyle(.plain)
    }
}
