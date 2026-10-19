import AntipodesCore
import AntipodesGlobe
import AntipodesStats
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// What a share card shows (R-SHARE-1).
enum ShareCard {
    case stat(title: String, value: String, detail: String?, symbol: String)
    case globe
    case trip(UUID)
    case journey(Journey)
    case year(Int)
}

enum ShareCardFormat: String, CaseIterable, Identifiable, Sendable {
    case square
    case story

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .square: "Square"
        case .story: "Story"
        }
    }

    /// Points; rendered at 3× for 1080-pixel-wide images.
    var size: CGSize {
        switch self {
        case .square: CGSize(width: 360, height: 360)
        case .story: CGSize(width: 360, height: 640)
        }
    }
}

/// Everything a card draws, captured as plain values so it can be rendered later,
/// off the screen it was shared from. No link, no account, no hosted page: the card is
/// an image made on the device (§10).
struct ShareCardPayload: Sendable {
    struct Metric: Sendable, Hashable {
        let label: String
        let value: String
    }

    var eyebrow: String
    var title: String
    var subtitle: String?
    var bigValue: String?
    var symbol: String?
    var metrics: [Metric] = []
    var scene: GlobeScene?
    var camera: GlobeCamera?
    var borders: CountryBorders?
}

extension ShareCardPayload {
    // One case per kind of card.
    // swiftlint:disable function_body_length
    @MainActor
    init(card: ShareCard, model: AppModel) {
        let statistics = model.statistics
        let system = model.rules.unitSystem
        let borders = model.globeBorders
        switch card {
        case let .stat(title, value, detail, symbol):
            let scene = GlobeSceneBuilder.build(log: model.log, rules: model.rules, arcSegments: 32)
            self.init(
                eyebrow: "My travels",
                title: title,
                subtitle: detail,
                bigValue: value,
                symbol: symbol,
                scene: scene,
                camera: scene.focusCoordinate.map { GlobeCamera(centre: $0, zoom: 1) },
                borders: borders
            )
        case .globe:
            let scene = GlobeSceneBuilder.build(log: model.log, rules: model.rules, arcSegments: 32)
            self.init(
                eyebrow: "My travels",
                title: "\(statistics.coverage.listedCountriesVisited) countries",
                subtitle: "\(Format.percent(statistics.coverage.worldFraction)) of the world",
                metrics: [
                    Metric(label: "Continents", value: "\(statistics.coverage.continentsVisited)"),
                    Metric(label: "Cities", value: "\(statistics.coverage.citiesVisited)"),
                    Metric(
                        label: "Travelled",
                        value: Format.distance(statistics.distance.totalKm, system)
                    ),
                ],
                scene: scene,
                camera: scene.focusCoordinate.map { GlobeCamera(centre: $0, zoom: 1) },
                borders: borders
            )
        case let .trip(tripID):
            let trip = model.log.trip(id: tripID)
            let stats = model.statistics(forTrip: tripID)
            let scene = GlobeSceneBuilder.build(
                log: model.log.restricted(toTrip: tripID),
                rules: model.rules
            )
            let span = model.dateSpan(ofTrip: tripID)
            self.init(
                eyebrow: "Trip",
                title: trip?.displayName(model: model) ?? "Trip",
                subtitle: span.map { Format.span($0.start, $0.end) },
                metrics: [
                    Metric(label: "Countries", value: "\(stats.coverage.countriesVisited)"),
                    Metric(label: "Places", value: "\(model.log.visits(inTrip: tripID).count)"),
                    Metric(
                        label: "Travelled",
                        value: Format.distance(stats.distance.totalKm, system)
                    ),
                ],
                scene: scene,
                camera: GlobeCamera
                    .framing(scene.pins.map(\.coordinate) + scene.arcs.flatMap(\.path)),
                borders: borders
            )
        case let .journey(journey):
            self.init(journey: journey, model: model)
        case let .year(year):
            let review = model.yearInReview(year)
            let scene = GlobeSceneBuilder.build(
                log: model.log.restricted(toYear: year),
                rules: model.rules
            )
            self.init(
                eyebrow: "Year in Review",
                title: String(year),
                subtitle: review.personality.map { "The year of the \($0.archetype.name)" },
                metrics: [
                    Metric(label: "Countries", value: "\(review.countries.count)"),
                    Metric(label: "New", value: "\(review.newCountries.count)"),
                    Metric(label: "Travelled", value: Format.distance(review.kilometres, system)),
                ],
                scene: scene,
                camera: scene.focusCoordinate.map { GlobeCamera(centre: $0, zoom: 1) },
                borders: borders
            )
        }
    }

    // swiftlint:enable function_body_length

    @MainActor
    private init(journey: Journey, model: AppModel) {
        let scene = GlobeSceneBuilder.build(
            log: TravelLog(journeys: [journey]),
            rules: model.rules
        )
        var metrics = [
            Metric(
                label: "Distance",
                value: Format.distance(journey.totalDistanceKm, model.rules.unitSystem)
            ),
        ]
        if let minutes = journey.elapsedMinutes {
            metrics.append(Metric(label: "Time", value: Format.duration(minutes: minutes)))
        }
        metrics.append(Metric(
            label: journey.legs.count == 1 ? "Mode" : "Legs",
            value: journey.legs.count == 1
                ? journey.legs[0].mode.displayName : "\(journey.legs.count)"
        ))
        self.init(
            eyebrow: journey.legs.first?.mode.displayName ?? "Journey",
            title: journey.displayTitle,
            subtitle: journey.date.isKnown ? journey.date.displayText : nil,
            symbol: journey.legs.first?.mode.symbolName,
            metrics: metrics,
            scene: scene,
            camera: GlobeCamera.framing(scene.arcs.flatMap(\.path)),
            borders: model.globeBorders
        )
    }
}

/// The card as drawn, at a fixed size.
struct ShareCardView: View {
    let payload: ShareCardPayload
    let format: ShareCardFormat

    var body: some View {
        ZStack {
            Palette.heroGradient
            VStack(spacing: 0) {
                globe
                    .frame(height: format == .story ? 360 : 200)
                    .padding(.top, format == .story ? 40 : 8)
                text
                Spacer(minLength: 0)
                footer
            }
        }
        .frame(width: format.size.width, height: format.size.height)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var globe: some View {
        if let scene = payload.scene {
            GlobeCanvas(
                scene: scene,
                borders: payload.borders,
                camera: payload.camera ?? .default,
                selection: nil,
                palette: GlobePalette(),
                rendersAsynchronously: false
            )
        } else {
            Color.clear
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(payload.eyebrow.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Palette.visited)
            if let bigValue = payload.bigValue {
                Text(bigValue)
                    .font(.statValue(format == .story ? 64 : 44))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Text(payload.title)
                .font(payload.bigValue == nil ? .title.weight(.bold) : .title3.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if let subtitle = payload.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
            if !payload.metrics.isEmpty {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(payload.metrics, id: \.self) { metric in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(metric.value)
                                .font(.statValue(17))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(metric.label)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe.europe.africa.fill")
            Text("Antipodes")
                .font(.footnote.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(.white.opacity(0.55))
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
    }
}

/// A card ready to hand to the share sheet as a PNG.
struct ShareCardImage: Transferable {
    let payload: ShareCardPayload
    var format: ShareCardFormat = .square

    @MainActor
    init(card: ShareCard, model: AppModel, format: ShareCardFormat = .square) {
        payload = ShareCardPayload(card: card, model: model)
        self.format = format
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            try await item.pngData()
        }
        .suggestedFileName("Antipodes.png")
    }

    @MainActor
    func render() -> CGImage? {
        let renderer = ImageRenderer(content: ShareCardView(payload: payload, format: format))
        renderer.scale = 3
        return renderer.cgImage
    }

    func pngData() async throws -> Data {
        guard let image = await render() else { throw CocoaError(.fileWriteUnknown) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        )
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }
}

/// Previews a card in both sizes and shares the one the user picks.
struct ShareCardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let card: ShareCard
    @State private var format: ShareCardFormat = .square

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Size", selection: $format) {
                    ForEach(ShareCardFormat.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                let image = ShareCardImage(card: card, model: model, format: format)
                ShareCardView(payload: image.payload, format: format)
                    .clipShape(.rect(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                    .scaleEffect(format == .story ? 0.72 : 0.92)
                    .frame(height: format == .story ? 470 : 340)

                ShareLink(
                    item: image,
                    preview: SharePreview("Antipodes", image: Image(systemName: "globe"))
                ) {
                    Label("Share Image", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal)
                Spacer(minLength: 0)
            }
            .padding(.top)
            .navigationTitle("Share")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
