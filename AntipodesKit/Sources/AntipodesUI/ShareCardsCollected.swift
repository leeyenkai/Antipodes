import AntipodesCore
import AntipodesStats
import SwiftUI

extension ShareCardPayload {
    /// Cards about what the user has collected rather than where: a personality, a
    /// badge, a collection. They carry their symbol instead of a globe.
    @MainActor
    init(collected card: ShareCard, model: AppModel) {
        switch card {
        case .personality:
            let themes = model.statistics.themes
            let archetype = themes.personality?.archetype ?? .wanderer
            self.init(
                eyebrow: "My travel personality",
                title: archetype.name,
                subtitle: archetype.summary,
                symbol: archetype.symbolName,
                metrics: themes.topThemes.prefix(3).map {
                    Metric(label: $0.label, value: Format.percent($0.share, digits: 0))
                }
            )
        case let .achievement(status):
            let progress = Format.percent(status.progress, digits: 0)
            let metric = status.earnedOn.map { Metric(label: "Earned", value: Format.day($0)) }
                ?? Metric(label: "Progress", value: progress)
            self.init(
                eyebrow: status.isEarned ? "Badge earned" : "Badge in progress",
                title: status.definition.name,
                subtitle: status.definition.description,
                symbol: status.definition.symbol ?? "star",
                metrics: [metric]
            )
        case let .collection(id):
            let progress = model.statistics.collections.first { $0.id == id }
            self.init(
                eyebrow: "Collection",
                title: progress?.definition.name ?? "Collection",
                subtitle: progress.map { Format.percent($0.fraction, digits: 0) + " visited" },
                bigValue: progress.map { "\($0.visitedCount) of \($0.total)" },
                symbol: progress?.definition.symbol ?? "square.stack.3d.up"
            )
        default:
            self.init(eyebrow: "My travels", title: "Antipodes")
        }
    }
}
