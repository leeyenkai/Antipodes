import AntipodesCore
import AntipodesGlobe
import AntipodesStats
import SwiftUI

/// A year of travel as a short run of animated cards (R-SHARE-3), built entirely from
/// the log on the device and shareable as images.
struct YearInReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let year: Int
    @State private var page = 0

    var body: some View {
        let review = model.yearInReview(year)
        let pages = pages(review)
        ZStack(alignment: .top) {
            Palette.heroGradient.ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, card in
                    ReviewPage(card: card, isActive: page == index)
                        .tag(index)
                        .padding(.horizontal, 24)
                        .padding(.top, 70)
                        .padding(.bottom, 50)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            #endif
            header(review)
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .onAppear { page = 0 }
    }

    private func header(_ review: YearInReview) -> some View {
        HStack {
            Text("\(String(year)) in review")
                .font(.headline)
            Spacer()
            ShareLink(
                item: ShareCardImage(card: .year(year), model: model, format: .story),
                preview: SharePreview("\(year) in review", image: Image(systemName: "sparkles"))
            ) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.glass)
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
        }
        .padding()
    }

    private func countriesLine(_ review: YearInReview) -> String {
        let noun = review.countries.count == 1 ? "country" : "countries"
        switch review.newCountries.count {
        case 0: return "\(noun) this year, all of them old friends"
        case review.countries.count: return review.countries.count == 1
            ? "\(noun), and a first visit" : "\(noun), every one of them new to you"
        default: return "\(noun) — \(review.newCountries.count) of them for the first time"
        }
    }

    // The cards in the order they are shown.
    // swiftlint:disable function_body_length
    private func pages(_ review: YearInReview) -> [ReviewCard] {
        let system = model.rules.unitSystem
        var cards: [ReviewCard] = [
            ReviewCard(
                eyebrow: "Your year",
                value: String(year),
                title: review.isEmpty ? "Nothing dated in this year" : "Here's where you went.",
                detail: review.undatedRecords > 0
                    ? """
                    \(Format.ordinalCount(review.undatedRecords, "record")) with no date aren't \
                    in any year.
                    """
                    : nil,
                scene: GlobeSceneBuilder.build(
                    log: model.log.restricted(toYear: year),
                    rules: model.rules
                ),
                symbol: "sparkles"
            ),
        ]
        cards.append(ReviewCard(
            eyebrow: "Countries",
            value: "\(review.countries.count)",
            title: countriesLine(review),
            detail: review.countries.sorted().map(Format.flag).joined(separator: " "),
            symbol: "flag.fill"
        ))
        cards.append(ReviewCard(
            eyebrow: "Distance",
            value: Format.distance(review.kilometres, system),
            title: """
            \(Format.multiple(review.kilometres / GreatCircle.earthCircumferenceKm)) round the Earth
            """,
            detail: [
                review.flights > 0 ? Format.ordinalCount(review.flights, "flight") : nil,
                Format.ordinalCount(review.legs, "leg"),
            ].compactMap(\.self).joined(separator: " · "),
            symbol: "point.topleft.down.to.point.bottomright.curvepath"
        ))
        if let longest = review.longestLeg {
            cards.append(ReviewCard(
                eyebrow: "Longest journey",
                value: Format.distance(longest.distanceKm, system),
                title: "\(longest.origin.name) → \(longest.destination.name)",
                detail: longest.date.displayText,
                symbol: longest.mode.symbolName
            ))
        }
        if review.daysAway > 0 || review.busiestMonth != nil {
            cards.append(ReviewCard(
                eyebrow: "Time away",
                value: "\(review.daysAway)",
                title: review.daysAway == 1 ? "day on the road" : "days on the road",
                detail: review.busiestMonth.map { "Busiest month: \(Format.monthName($0.month))" },
                symbol: "sun.max.fill"
            ))
        }
        if let personality = review.personality {
            let shifted = review.personalityBefore
                .map { $0.archetype != personality.archetype } ?? false
            cards.append(ReviewCard(
                eyebrow: "Your year's personality",
                value: personality.archetype.name,
                title: shifted
                    ? "A change from \(review.personalityBefore?.archetype.name ?? "before")"
                    : personality.archetype.summary,
                detail: review.topThemes.map(\.label).joined(separator: " · "),
                symbol: personality.archetype.symbolName
            ))
        }
        if let carbon = review.carbonKg, carbon > 0 {
            cards.append(ReviewCard(
                eyebrow: "Carbon (estimate)",
                value: Format.carbon(kilograms: carbon),
                title: "from every leg you logged",
                detail: "Estimated from \(model.catalogue.emissionFactors.sourceName) factors.",
                symbol: "leaf.fill"
            ))
        }
        cards.append(ReviewCard(
            eyebrow: "\(year) in short",
            value: "\(review.places)",
            title: """
            places · \(review.countries.count) countries · \(review.continents.count) continents
            """,
            detail: "Share it with the button above. Made on your device; nothing is uploaded.",
            scene: GlobeSceneBuilder.build(
                log: model.log.restricted(toYear: year),
                rules: model.rules
            ),
            symbol: "globe"
        ))
        return cards
    }
    // swiftlint:enable function_body_length
}

struct ReviewCard {
    var eyebrow: String
    var value: String
    var title: String
    var detail: String?
    var scene: GlobeScene?
    var symbol: String
}

private struct ReviewPage: View {
    @Environment(GlobeBorderStore.self) private var borderStore
    let card: ReviewCard
    let isActive: Bool
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let scene = card.scene {
                GlobeCanvas(
                    scene: scene,
                    borders: borderStore.coarse,
                    camera: scene.focusCoordinate
                        .map { GlobeCamera(centre: $0, zoom: 1) } ?? .default,
                    selection: nil,
                    palette: GlobePalette()
                )
                .frame(maxHeight: 320)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
            } else {
                Spacer(minLength: 40)
                Image(systemName: card.symbol)
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(Palette.visited)
                    .symbolEffect(.bounce, value: appeared)
            }
            Text(card.eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(Palette.visited)
            Text(card.value)
                .font(.statValue(64))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.numericText())
                .offset(y: appeared ? 0 : 24)
                .opacity(appeared ? 1 : 0)
            Text(card.title)
                .font(.title2.weight(.semibold))
                .opacity(appeared ? 1 : 0)
            if let detail = card.detail, !detail.isEmpty {
                Text(detail)
                    .font(detail.unicodeScalars
                        .allSatisfy { $0.properties.isEmojiPresentation || $0 == " " }
                        ? .largeTitle : .body)
                    .foregroundStyle(.white.opacity(0.7))
                    .opacity(appeared ? 1 : 0)
            }
            Spacer()
        }
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity)
        .onChange(of: isActive, initial: true) { _, active in
            if active {
                appeared = false
                withAnimation(.spring(duration: 0.7, bounce: 0.25).delay(0.1)) { appeared = true }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
