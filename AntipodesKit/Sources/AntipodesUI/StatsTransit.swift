import AntipodesCore
import AntipodesStats
import SwiftUI

/// City transit (§7): systems, lines and stations, and how much of each network has
/// been ridden, counted in segments (R-TRAN-2, R-TRAN-3).
struct TransitSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let transit = model.shownStatistics.transit
        if transit.rides > 0 {
            StatsSection(
                title: "City transit",
                symbol: "tram.fill.tunnel",
                caveat: caveat(transit)
            ) {
                StatCardList {
                    StatRow(
                        "Systems ridden",
                        "\(transit.systems.count)",
                        symbol: "map",
                        detail: transit.systems.prefix(3).map(\.system.name)
                            .joined(separator: ", "),
                        route: .transitSystems
                    )
                    StatRow(
                        "Lines ridden",
                        "\(transit.linesRidden)",
                        symbol: "point.3.connected.trianglepath.dotted",
                        route: .transitSystems
                    )
                    StatRow(
                        "Stations",
                        "\(transit.stationsVisited.count)",
                        symbol: "tram.fill.tunnel",
                        detail: """
                        \(transit.boarded.count) boarded, \(transit.alighted.count) alighted, \
                        \(transit.passedThrough.count) passed through
                        """,
                        route: .transitSystems
                    )
                    StatRow(
                        "Rides",
                        "\(transit.rides)",
                        symbol: "repeat",
                        route: .legs(.cityTransit)
                    )
                }
                if !transit.systems.isEmpty {
                    StatCardList {
                        ForEach(transit.systems.prefix(4)) { system in
                            NavigationLink(value: StatsRoute.transitSystem(system.system.id)) {
                                SystemCoverageRow(coverage: system)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func caveat(_ transit: TransitStatistics) -> String? {
        transit.input.caveat(counting: "rides")
    }
}

/// A system with the share of it ridden.
private struct SystemCoverageRow: View {
    let coverage: TransitSystemCoverage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(coverage.system.name)
                Spacer(minLength: 8)
                Text(Format.percent(coverage.fraction))
                    .font(.body.weight(.medium).monospacedDigit())
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            ProgressView(value: coverage.fraction)
                .tint(Palette.mode(.cityTransit))
            Text("""
            \(coverage.segmentsRidden) of \(coverage.segmentsTotal) segments · \
            \(Format.ordinalCount(coverage.linesRidden, "line")) · \
            \(Format.ordinalCount(coverage.stationsVisited, "station"))
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Every system ridden.
struct TransitSystemsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let transit = model.shownStatistics.transit
        List {
            Section {
                ForEach(transit.systems) { system in
                    NavigationLink(value: StatsRoute.transitSystem(system.system.id)) {
                        SystemCoverageRow(coverage: system)
                    }
                }
            } footer: {
                Text("""
                A segment is the stretch between two neighbouring stops on a line; riding it \
                again adds a ride, not coverage. Networks from Wikidata.
                """)
            }
        }
        .navigationTitle("City transit")
    }
}

/// One system's lines, each with the share of it ridden.
struct TransitSystemDetailView: View {
    @Environment(AppModel.self) private var model
    let systemID: Int64

    var body: some View {
        let transit = model.shownStatistics.transit
        if let system = transit.systems.first(where: { $0.system.id == systemID }) {
            List {
                Section {
                    LabeledContent("Ridden", value: Format.percent(system.fraction))
                    LabeledContent(
                        "Segments",
                        value: "\(system.segmentsRidden) of \(system.segmentsTotal)"
                    )
                    LabeledContent("Rides", value: "\(system.rides)")
                }
                Section("Lines") {
                    ForEach(system.lines) { line in
                        HStack {
                            TransitLineLabel(line: line.line)
                            Spacer(minLength: 8)
                            Text(line.segmentsRidden == 0 ? "—" : Format.percent(
                                line.fraction,
                                digits: 0
                            ))
                            .monospacedDigit()
                            .foregroundStyle(line.segmentsRidden == 0 ? .tertiary : .secondary)
                        }
                    }
                }
            }
            .navigationTitle(system.system.name)
        } else {
            ContentUnavailableView("Not ridden yet", systemImage: "tram.fill.tunnel")
        }
    }
}
