import AntipodesCore
import AntipodesStats
import SwiftUI

/// Temperature in the month visited and the climate zones reached (R-CALC-2, §7).
struct ClimateRows: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let climate = model.shownStatistics.climate
        let system = model.rules.unitSystem
        if climate.temperatureInput.used > 0 || !climate.zones.isEmpty {
            StatCardList {
                if let average = climate.averageTemperatureC {
                    StatRow(
                        "Average temperature",
                        Format.temperature(average, system),
                        symbol: "thermometer.medium",
                        detail: temperatureDetail(climate),
                        route: .temperatures
                    )
                }
                if let hottest = climate.hottest {
                    StatRow(
                        "Warmest visit",
                        Format.temperature(hottest.temperatureC, system),
                        symbol: "sun.max",
                        detail: "\(hottest.place.name), \(hottest.date.displayText)",
                        route: .temperatures
                    )
                }
                if let coldest = climate.coldest, coldest != climate.hottest {
                    StatRow(
                        "Coldest visit",
                        Format.temperature(coldest.temperatureC, system),
                        symbol: "snowflake",
                        detail: "\(coldest.place.name), \(coldest.date.displayText)",
                        route: .temperatures
                    )
                }
                if !climate.zones.isEmpty {
                    StatRow(
                        "Climate zones",
                        "\(climate.zones.count)",
                        symbol: "cloud.sun",
                        detail: climate.zoneInput.caveat(counting: "places")
                            ?? ClimateZone.Group.allCases.filter(climate.groups.contains)
                            .map(\.name).joined(separator: " · "),
                        route: .grouped(.climateZones)
                    )
                }
            }
            Text("""
            Usual temperatures for the month and place — the 1991–2020 average from \
            TerraClimate — not the weather on the day.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// The caveat, and how many visits dated only by year used the year's mean.
    private func temperatureDetail(_ climate: ClimateStatistics) -> String? {
        var parts: [String] = []
        if let caveat = climate.temperatureInput.caveat(counting: "visits") {
            parts.append(caveat)
        }
        if climate.annualMeanCount > 0 {
            parts.append(
                "\(Format.ordinalCount(climate.annualMeanCount, "visit")) dated only by year "
                    + "use the year's average."
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
