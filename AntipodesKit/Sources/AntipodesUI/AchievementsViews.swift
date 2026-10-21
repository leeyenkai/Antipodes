import AntipodesCore
import AntipodesStats
import SwiftUI

struct AchievementsGrid: View {
    @Environment(AppModel.self) private var model
    @State private var selected: AchievementStatus?

    var body: some View {
        let achievements = model.statistics.achievements
        let earned = achievements.filter(\.isEarned).count
        if achievements.isEmpty {
            ContentUnavailableView(
                "Badges unavailable",
                systemImage: "rosette",
                description: Text("""
                The badges come with the built-in list of places, which couldn't be read. \
                Your log is safe; reinstalling Antipodes should bring them back.
                """)
            )
        } else {
            grid(achievements, earned: earned)
        }
    }

    private func grid(_ achievements: [AchievementStatus], earned: Int) -> some View {
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
            // Scrolls, so a large text size never pushes the progress off the sheet.
            ScrollView {
                content
            }
            .navigationTitle(status.definition.name)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.success, trigger: status.isEarned) { _, earned in earned }
    }

    private var content: some View {
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
        }
        .padding()
        .frame(maxWidth: .infinity)
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
