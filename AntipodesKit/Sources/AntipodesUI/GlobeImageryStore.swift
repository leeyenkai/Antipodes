import AntipodesGlobe
import CoreGraphics
import Foundation
import ImageIO
import Observation
import os

/// Loads the picture of the Earth the satellite globe wraps round the sphere (D-26).
///
/// The picture ships in the app, scaled from NASA's Blue Marble by
/// `scripts/fetch-imagery.sh`; nothing is fetched. Decoded it is 32 MB, so it is read
/// only while the satellite style is chosen and let go when it is not.
@MainActor
@Observable
final class GlobeImageryStore {
    private(set) var image: EquirectangularImage?
    /// Why the satellite style cannot be shown, if it cannot.
    private(set) var failure: String?
    /// The last few globes drawn from the picture, so redrawing the same view — a
    /// selection changing, a sheet opening over it — does not redo the work.
    let rasters = GlobeRasterCache()

    @ObservationIgnored private var loading: Task<Void, Never>?
    private let locate: @Sendable () -> URL?

    init(locate: @escaping @Sendable () -> URL? = GlobeImageryStore.bundled) {
        self.locate = locate
    }

    static let bundled: @Sendable () -> URL? = {
        Bundle.main.url(forResource: "earth-satellite", withExtension: "jpg")
    }

    /// Whether this copy of the app carries the picture at all.
    var isAvailable: Bool {
        locate() != nil
    }

    func load() {
        guard image == nil, loading == nil else { return }
        guard let url = locate() else {
            failure = Self.unavailable(detail: "earth-satellite.jpg is not in the bundle: "
                + "run scripts/fetch-imagery.sh.")
            return
        }
        loading = Task {
            // A couple of hundred milliseconds of JPEG decoding: off the main actor.
            let decoded = await Task.detached(priority: .userInitiated) {
                Self.decode(url)
            }.value
            // Switched back to the standard globe meanwhile: keep none of the 33 MB, and
            // leave `loading` to whatever load may have started since.
            guard !Task.isCancelled else { return }
            image = decoded
            failure = decoded == nil ? Self.unavailable(detail: "could not decode it.") : nil
            loading = nil
        }
    }

    func unload() {
        loading?.cancel()
        loading = nil
        image = nil
        rasters.removeAll()
    }

    private static func unavailable(detail: String) -> String {
        var message = "The satellite globe isn't available in this copy of Antipodes. "
            + "Reinstalling should fix it."
        #if DEBUG
            message += " (\(detail))"
        #endif
        return message
    }

    /// The JPEG as four bytes a pixel, red first.
    nonisolated static func decode(_ url: URL) -> EquirectangularImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let picture = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let width = picture.width
        let height = picture.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return EquirectangularImage(width: width, height: height, pixels: pixels)
    }
}

/// Globes already drawn from the picture, by camera, view size and resolution.
///
/// Read and written from the canvas, which may draw off the main thread, so it guards
/// itself with a lock rather than an actor: drawing cannot wait.
final class GlobeRasterCache: Sendable {
    struct Key: Hashable, Sendable {
        let camera: GlobeCamera
        let width: Double
        let height: Double
        let scale: Double
    }

    struct Entry: @unchecked Sendable {
        /// Immutable once made, so it is safe to hand between threads.
        let image: CGImage
        /// Where it goes in the view, in points.
        let frame: CGRect
        let scale: Double
    }

    private let entries = OSAllocatedUnfairLock<[(key: Key, entry: Entry)]>(initialState: [])
    private static let capacity = 4

    func entry(for key: Key) -> Entry? {
        entries.withLock { list in list.first { $0.key == key }?.entry }
    }

    func store(_ entry: Entry, for key: Key) {
        entries.withLock { list in
            list.removeAll { $0.key == key }
            list.insert((key, entry), at: 0)
            if list.count > Self.capacity {
                list.removeLast(list.count - Self.capacity)
            }
        }
    }

    func removeAll() {
        entries.withLock { $0.removeAll() }
    }
}

extension GlobeRaster {
    /// The raster as an image Core Graphics can draw.
    var cgImage: CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
