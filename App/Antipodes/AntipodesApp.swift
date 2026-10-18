import AntipodesStore
import AntipodesUI
import SwiftUI

/// The app entry point.
///
/// Everything of substance lives in the `AntipodesKit` package; this target exists to
/// host `@main`, bundle the place database and carry the app's assets and
/// entitlements (decision D-3).
@main
struct AntipodesApp: App {
    @State private var model: AppModel

    init() {
        model = AppModel(
            store: Self.makeStore(),
            placeDatabaseURL: Self.placeDatabaseURL()
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif
    }

    /// Opens the on-disk store, falling back to memory if that is impossible.
    ///
    /// A failure here is almost always a missing or mismatched iCloud entitlement in a
    /// development build. Falling back keeps the app usable and loses nothing that was
    /// already saved, because the on-disk store is left untouched. It is the wrong
    /// behaviour for a release build, where silently not persisting would be worse
    /// than refusing to start — hence the assertion.
    private static func makeStore() -> TravelLogStore {
        do {
            return try TravelLogStore()
        } catch {
            assertionFailure("Could not open the travel log store: \(error)")
            do {
                return try TravelLogStore(inMemory: true)
            } catch {
                fatalError("Could not create even an in-memory store: \(error)")
            }
        }
    }

    /// The read-only place database shipped in the bundle.
    ///
    /// Built by `scripts/build-placedb.sh`, which is not run automatically — if it is
    /// missing, search reports that rather than coming back empty (R-DB-4).
    private static func placeDatabaseURL() -> URL? {
        Bundle.main.url(forResource: "places", withExtension: "sqlite")
    }
}
