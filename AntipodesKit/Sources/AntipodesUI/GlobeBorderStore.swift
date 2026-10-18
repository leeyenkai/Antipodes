import AntipodesGlobe
import Foundation
import Observation

/// Loads the bundled country outlines the globe shades (R-GLOBE-2).
///
/// Two resolutions ship: 1:110m for the whole globe, and 1:50m once it is zoomed in far
/// enough that the coarse outline would show. The coarse one is small enough to decode
/// on the spot; the fine one is about 100,000 points and takes long enough that it is
/// decoded off the main actor, the first time the zoom actually calls for it.
///
/// Missing files are a build-configuration problem, not a crash: the globe still draws
/// its graticule, pins and arcs, and the screen says shading is unavailable and how to
/// fix it (`scripts/fetch-borders.sh`).
@MainActor
@Observable
public final class GlobeBorderStore {
    public enum Resolution: String, Sendable, CaseIterable {
        case coarse = "borders-110m"
        case fine = "borders-50m"

        /// Above this zoom the 1:110m outline starts to look like a polygon rather than
        /// a coastline, so the finer one takes over.
        static let fineZoomThreshold = 2.5
    }

    public private(set) var coarse: CountryBorders?
    public private(set) var fine: CountryBorders?
    /// Why the outlines are not there, for the screen to show rather than silently
    /// drawing an unshaded globe.
    public private(set) var failure: String?

    private var isLoadingFine = false
    private let locate: @Sendable (Resolution) -> URL?

    /// `locate` is injectable so previews and tests can stand in their own files; the
    /// default reads the app bundle, where `scripts/build-borders.sh` puts them.
    public init(locate: @escaping @Sendable (Resolution) -> URL? = GlobeBorderStore.bundled) {
        self.locate = locate
    }

    public static let bundled: @Sendable (Resolution) -> URL? = { resolution in
        Bundle.main.url(forResource: resolution.rawValue, withExtension: "antborders")
    }

    public var hasBorders: Bool {
        coarse != nil || fine != nil
    }

    /// The best outlines available for a zoom level, falling back rather than drawing
    /// nothing.
    public func borders(forZoom zoom: Double) -> CountryBorders? {
        if zoom >= Resolution.fineZoomThreshold {
            if let fine {
                return fine
            }
            loadFineIfNeeded()
        }
        return coarse ?? fine
    }

    public func loadCoarse() {
        guard coarse == nil else { return }
        guard let url = locate(.coarse) else {
            failure = """
            Country outlines are not in the app bundle. Run scripts/fetch-borders.sh \
            and scripts/build-borders.sh, then rebuild.
            """
            return
        }
        do {
            coarse = try CountryBorders.load(from: url)
            failure = nil
        } catch {
            failure = "Country outlines could not be read: \(error)"
        }
    }

    private func loadFineIfNeeded() {
        guard fine == nil, !isLoadingFine, let url = locate(.fine) else { return }
        isLoadingFine = true
        Task {
            // Roughly 70 ms of decoding, which would be a visible stutter mid-pinch.
            let loaded = await Task.detached(priority: .userInitiated) {
                try? CountryBorders.load(from: url)
            }.value
            fine = loaded
            isLoadingFine = false
        }
    }
}
