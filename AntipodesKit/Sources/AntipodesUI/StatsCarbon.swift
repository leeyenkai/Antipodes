import AntipodesCore
import AntipodesStats
import Charts
import SwiftUI

// MARK: - Carbon

struct CarbonSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let carbon = model.statistics.carbon
        if carbon.input.used > 0 {
            StatsSection(
                title: "Carbon",
                symbol: "leaf",
                caveat: carbon.input.caveat(counting: "legs")
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Format.carbon(kilograms: carbon.totalKg))
                        .font(.statValue(34))
                    Text("Estimated for every leg you've logged.")
                        .foregroundStyle(.secondary)
                    if carbon.totalSavedKg > 0 {
                        Label(
                            """
                            \(Format.carbon(kilograms: carbon.totalSavedKg)) saved by going \
                            overland instead of flying
                            """,
                            systemImage: "arrow.down.forward"
                        )
                        .foregroundStyle(Palette.visited)
                    }
                    if !carbon.kgByYear.isEmpty {
                        CarbonByYearChart(kgByYear: carbon.kgByYear)
                    }
                    Text(sourceLine(carbon))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .card()
                StatCardList {
                    ForEach(
                        carbon.kgByMode.sorted { $0.value > $1.value },
                        id: \.key
                    ) { mode, kilograms in
                        StatRow(
                            mode.displayName,
                            Format.carbon(kilograms: kilograms),
                            symbol: mode.symbolName,
                            route: .legs(mode)
                        )
                    }
                    StatRow("Every leg", "", symbol: "list.bullet", route: .carbon)
                }
            }
        }
    }

    /// R-CO2-3: every carbon figure says it is an estimate, and whose factors.
    private func sourceLine(_ carbon: CarbonStatistics) -> String {
        var line = "An estimate: distance × \(carbon.sourceName)"
        if let year = carbon.factorYear, !carbon.sourceName.contains(String(year)) {
            line += " (\(year))"
        }
        line += " factors per passenger-km, flights including radiative forcing."
        if carbon.vehicleBasisLegs > 0 {
            line += " Road trips count the whole vehicle — divide by the people sharing it."
        }
        return line
    }
}

private struct CarbonByYearChart: View {
    let kgByYear: [Int: Double]

    var body: some View {
        Chart(kgByYear.sorted { $0.key < $1.key }, id: \.key) { year, kilograms in
            BarMark(x: .value("Year", String(year)), y: .value("kg CO₂e", kilograms))
                .foregroundStyle(Palette.visited.gradient)
                .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let kilograms = value.as(Double.self) {
                        Text(Format.compact(kilograms))
                    }
                }
            }
        }
        .frame(height: 140)
    }
}
