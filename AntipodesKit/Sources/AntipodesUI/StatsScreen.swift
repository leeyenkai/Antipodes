import AntipodesCore
import AntipodesStats
import SwiftUI

/// The stats dashboard (§9).
///
/// Every number carries its caveat, so the user can see what it rests on (R-CALC-5).
/// M1 ships the coverage and distance families; the other three land in v1 (§13).
struct StatsScreen: View {
    @Environment(AppModel.self) private var model

    private var statistics: TravelStatistics {
        model.statistics
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(statistics.headlines) { StatCard(headline: $0) }
                    }
                    .padding(.vertical, 4)
                }

                coverageSection
                distanceSection
                extremesSection

                Section {
                    Text("""
                    Place attributes, time and patterns, and culture and themes arrive \
                    in v1. Coverage and distance ship first.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Stats")
        }
    }

    private var coverageSection: some View {
        Section("Coverage") {
            let coverage = statistics.coverage
            LabeledContent("Countries", value: "\(coverage.countriesVisited)")
            LabeledContent(
                "Share of the world",
                value: String(format: "%.1f%%", coverage.worldFraction * 100)
            )
            LabeledContent(
                "Continents",
                value: "\(coverage.continentsVisited) of \(Continent.allSeven.count)"
            )
            LabeledContent("Regions", value: "\(coverage.regionsVisited)")
            LabeledContent("Cities", value: "\(coverage.citiesVisited)")
            LabeledContent("Landmarks", value: "\(coverage.landmarksVisited)")
            LabeledContent("Airports", value: "\(coverage.airportsVisited)")

            if let caveat = coverage.input.caveat {
                CaveatLabel(text: caveat)
            }
            Text("Measured against \(coverage.worldCountryCount) countries.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var distanceSection: some View {
        Section("Distance") {
            let distance = statistics.distance
            LabeledContent("Total", value: statistics.formattedDistance)
            LabeledContent(
                "Round the Earth",
                value: String(format: "%.2f×", distance.timesRoundTheEarth)
            )

            ForEach(distance.modesSortedByDistance, id: \.mode) { entry in
                LabeledContent {
                    Text(formatted(entry.kilometres))
                } label: {
                    Label(entry.mode.displayName, systemImage: entry.mode.symbolName)
                }
            }

            if let longest = distance.longestLeg {
                LabeledContent("Longest leg") {
                    Text("\(longest.origin.name) → \(longest.destination.name)")
                        .multilineTextAlignment(.trailing)
                }
            }

            if distance.approximateLegCount > 0 {
                CaveatLabel(
                    text: """
                    \(distance.approximateLegCount) leg\
                    \(distance.approximateLegCount == 1 ? "" : "s") \
                    (\(formatted(distance.approximateKm))) use a straight line because \
                    no real path is available yet.
                    """
                )
            }
            if let caveat = distance.input.caveat {
                CaveatLabel(text: caveat)
            }
        }
    }

    private var extremesSection: some View {
        Section("Extreme points") {
            let extremes = statistics.extremes
            extremeRow("Northernmost", extremes.northernmost)
            extremeRow("Southernmost", extremes.southernmost)
            extremeRow("Easternmost", extremes.easternmost)
            extremeRow("Westernmost", extremes.westernmost)
            if let caveat = extremes.input.caveat {
                CaveatLabel(text: caveat)
            }
        }
    }

    private func extremeRow(_ title: String, _ visit: Visit?) -> some View {
        LabeledContent(title, value: visit?.place.name ?? "—")
    }

    private func formatted(_ kilometres: Double) -> String {
        let value = model.rules.unitSystem.distance(fromKilometres: kilometres)
        return "\(Int(value.rounded())) \(model.rules.unitSystem.distanceUnitAbbreviation)"
    }
}
