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
    @State private var opening: Result<AppModel, any Error>

    init() {
        _opening = State(initialValue: Self.open())
    }

    var body: some Scene {
        WindowGroup {
            switch opening {
            case let .success(model):
                RootView()
                    .environment(model)
            case let .failure(error):
                StoreUnavailableView(error: error) { opening = Self.open() }
            }
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif
        .commands {
            if case let .success(model) = opening {
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
    }

    /// Opens the on-disk store and the model around it.
    ///
    /// A failure is shown rather than papered over with an in-memory store: carrying
    /// on would look fine and then lose everything logged at the next launch.
    private static func open() -> Result<AppModel, any Error> {
        Result {
            try AppModel(
                store: TravelLogStore(),
                placeDatabaseURL: Bundle.main.url(forResource: "places", withExtension: "sqlite"),
                bordersURL: Bundle.main.url(forResource: "borders-50m", withExtension: "antborders")
            )
        }
    }
}
