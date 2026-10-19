import AntipodesStore
import AntipodesUI
import SwiftUI

/// The app entry point.
///
/// Everything of substance lives in the `AntipodesKit` package; this target exists to
/// host `@main`, bundle the place database and the country outlines, and carry the
/// app's assets and entitlements (decision D-3).
@main
struct AntipodesApp: App {
    @State private var model: AppModel

    init() {
        model = AppModel(
            store: Self.makeStore(),
            placeDatabaseURL: Bundle.main.url(forResource: "places", withExtension: "sqlite"),
            bordersURL: Bundle.main.url(forResource: "borders-50m", withExtension: "antborders")
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Log a Place…") { model.addRequest = AddRequest() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Log a Journey…") { model.addRequest = AddRequest(start: .journey(nil)) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Drop a Pin…") { model.addRequest = AddRequest(start: .pin(nil)) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
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
}
