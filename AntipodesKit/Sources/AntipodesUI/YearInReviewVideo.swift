import AntipodesGlobe
import AVFoundation
import AVKit
import CoreVideo
import SwiftUI

/// Year in Review as a short video (R-SHARE-3), made entirely on the device.
///
/// Each card is drawn once as a 1080 × 1920 still, the size stories take, and the stills
/// are written to an H.264 file with a short cross-fade between them. Drawing needs the
/// main actor; encoding does not, so it runs beside it and the screen stays live.
enum YearInReviewVideo {
    static let size = CGSize(width: 1080, height: 1920)
    static let framesPerSecond: Int32 = 30
    /// How long each card holds, and how long the fade into the next one takes.
    static let holdFrames = 75
    static let fadeFrames = 15

    enum Failure: Error, LocalizedError {
        case drawing
        case encoding(String)

        var errorDescription: String? {
            switch self {
            case .drawing: "The cards couldn't be drawn."
            case let .encoding(reason): "The video couldn't be made. \(reason)"
            }
        }
    }

    /// The year's cards drawn as stills, in order.
    @MainActor
    static func stills(
        _ cards: [ReviewCard],
        year: Int,
        borders: CountryBorders?
    ) throws -> [CGImage] {
        try cards.map { card in
            guard let image = ShareCardRenderer.render(
                ReviewStoryFrame(card: card, year: year, borders: borders)
            ) else { throw Failure.drawing }
            return image
        }
    }

    /// Writes the stills to an MP4 in the temporary directory and returns where.
    /// `progress` is told how far it has got, from 0 to 1.
    static func encode(
        _ stills: Stills,
        year: Int,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "Antipodes \(year) in review.mp4")
        try? FileManager.default.removeItem(at: url)
        // Detached to keep the encoding off the main actor, but tied to the caller: the
        // sheet closing cancels it rather than leaving it to run on, unseen, and write a
        // file nobody will share.
        let encoding = Task.detached(priority: .userInitiated) {
            try await write(stills.images, to: url, progress: progress)
        }
        do {
            try await withTaskCancellationHandler {
                try await encoding.value
            } onCancel: {
                encoding.cancel()
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return url
    }

    /// CGImage is immutable once made, so a list of them can cross to the encoder.
    struct Stills: @unchecked Sendable {
        let images: [CGImage]
    }

    /// Each card holds, then fades into the next; the last one only holds.
    private static func framePlan(cardCount: Int) -> [(from: Int, to: Int, mix: Double)] {
        var plan: [(from: Int, to: Int, mix: Double)] = []
        for index in 0 ..< cardCount {
            plan += Array(repeating: (index, index, 0), count: holdFrames)
            if index < cardCount - 1 {
                plan += (1 ... fadeFrames).map { (
                    index,
                    index + 1,
                    Double($0) / Double(fadeFrames + 1)
                ) }
            }
        }
        return plan
    }

    private static func write(
        _ images: [CGImage],
        to url: URL,
        progress: @Sendable (Double) -> Void
    ) async throws {
        guard !images.isEmpty else { throw Failure.drawing }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ]
        )
        writer.add(input)
        guard writer.startWriting() else {
            throw Failure.encoding(writer.error?.localizedDescription ?? "")
        }
        writer.startSession(atSourceTime: .zero)

        let plan = framePlan(cardCount: images.count)

        for (frame, step) in plan.enumerated() {
            if Task.isCancelled {
                writer.cancelWriting()
                throw CancellationError()
            }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let pool = adaptor.pixelBufferPool,
                  let buffer = Self.buffer(
                      from: pool,
                      drawing: images[step.from],
                      fadingTo: images[step.to],
                      mix: step.mix
                  )
            else { throw Failure.encoding("No memory for a frame.") }
            let time = CMTime(value: CMTimeValue(frame), timescale: framesPerSecond)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw Failure.encoding(writer.error?.localizedDescription ?? "")
            }
            if frame.isMultiple(of: 15) {
                progress(Double(frame) / Double(plan.count))
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw Failure.encoding(writer.error?.localizedDescription ?? "")
        }
        progress(1)
    }

    private static func buffer(
        from pool: CVPixelBufferPool,
        drawing first: CGImage,
        fadingTo second: CGImage,
        mix: Double
    ) -> CVPixelBuffer? {
        var made: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
        guard let buffer = made else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        let frame = CGRect(origin: .zero, size: size)
        context.draw(first, in: frame)
        if mix > 0 {
            context.setAlpha(mix)
            context.draw(second, in: frame)
        }
        return buffer
    }
}

/// One Year in Review card laid out as a story-sized still, for the video and for
/// sharing the cards as images. The same content as the animated page, standing still.
struct ReviewStoryFrame: View {
    let card: ReviewCard
    let year: Int
    let borders: CountryBorders?

    var body: some View {
        ZStack {
            Palette.heroGradient
            VStack(alignment: .leading, spacing: 14) {
                if let scene = card.scene {
                    GlobeCanvas(
                        scene: scene,
                        borders: borders,
                        camera: scene.focusCoordinate
                            .map { GlobeCamera(centre: $0, zoom: 1) } ?? .default,
                        selection: nil,
                        palette: GlobePalette(),
                        rendersAsynchronously: false
                    )
                    .frame(height: 300)
                } else {
                    Spacer(minLength: 60)
                    Image(systemName: card.symbol)
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Palette.visited)
                }
                Text(card.eyebrow.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Palette.visited)
                Text(card.value)
                    .font(.statValue(60))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(card.title)
                    .font(.display(.title3))
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                if let detail = card.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(4)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    AppMark(size: 16)
                    Text("Antipodes · \(String(year)) in review")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.55))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .padding(.vertical, 30)
        }
        .frame(width: 360, height: 640)
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(.large)
    }
}

/// Shares a year as a video, as every card as images, or as one summary card.
struct YearInReviewShareSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let year: Int
    let cards: [ReviewCard]

    @State private var images: [RenderedImage] = []
    @State private var video: URL?
    @State private var progress = 0.0
    @State private var failure: String?
    @State private var isSharingSummary = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    preview
                        .frame(height: 420)
                        .clipShape(.rect(cornerRadius: 22, style: .continuous))
                        .padding(.horizontal, 60)
                    if let video {
                        ShareLink(item: video, preview: SharePreview("\(String(year)) in review")) {
                            Label("Share Video", systemImage: "play.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    } else if let failure {
                        CaveatLabel(text: failure)
                    } else {
                        ProgressView("Making the video…", value: progress)
                    }
                    if !images.isEmpty {
                        ShareLink(
                            items: images,
                            preview: { SharePreview($0.name, image: $0.swiftUIImage) },
                            label: {
                                Label(
                                    "Share \(images.count) Cards as Images",
                                    systemImage: "photo.stack"
                                )
                                .frame(maxWidth: .infinity)
                            }
                        )
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }
                    Button("Share One Summary Card", systemImage: "rectangle.portrait") {
                        isSharingSummary = true
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    Text("Made on this device from your log. Nothing is uploaded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Share \(String(year))")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isSharingSummary) { ShareCardSheet(card: .year(year)) }
            .task { await make() }
            .onDisappear {
                if let video {
                    try? FileManager.default.removeItem(at: video)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 680, idealHeight: 760)
        #endif
    }

    @ViewBuilder
    private var preview: some View {
        if let video {
            VideoPlayer(player: AVPlayer(url: video))
        } else if let first = images.first {
            first.swiftUIImage.resizable().scaledToFit()
        } else {
            Palette.heroGradient
        }
    }

    private func make() async {
        do {
            let stills = try YearInReviewVideo.stills(
                cards,
                year: year,
                borders: model.globeBorders
            )
            images = stills.enumerated().map { index, image in
                RenderedImage(image: image, name: "Antipodes \(year) – \(index + 1)")
            }
            video = try await YearInReviewVideo
                .encode(.init(images: stills), year: year) { fraction in
                    Task { @MainActor in progress = fraction }
                }
        } catch is CancellationError {
            // The sheet closed; there is no one to tell.
        } catch {
            failure = error.localizedDescription
        }
    }
}
