import SwiftUI

/// The app's menu commands, with their keyboard shortcuts (R-NAV-2): logging from the
/// File menu, and on the Mac, ⌘1 to ⌘4 for the four main sections.
public struct AppCommands: Commands {
    let model: AppModel
    @FocusedValue(\.selectSection) private var selectSection

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Log a Place…") { model.addRequest = AddRequest() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Log a Journey…") { model.addRequest = AddRequest(start: .journey(nil)) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Drop a Pin…") { model.addRequest = AddRequest(start: .pin(nil)) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
        }
        CommandGroup(before: .sidebar) {
            Button("Globe") { selectSection?(.globe) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Trips") { selectSection?(.trips) }
                .keyboardShortcut("2", modifiers: .command)
            Button("Stats") { selectSection?(.stats) }
                .keyboardShortcut("3", modifiers: .command)
            Button("Collections") { selectSection?(.collections) }
                .keyboardShortcut("4", modifiers: .command)
            Button("All Records") { selectSection?(.records) }
                .keyboardShortcut("5", modifiers: .command)
            Divider()
        }
    }
}

extension FocusedValues {
    /// Switches the window's section, for the menu's ⌘1 to ⌘5.
    @Entry var selectSection: SectionSelector?
}

/// A section of the main window, as the menu names them.
public enum AppSection: Sendable {
    case globe
    case trips
    case stats
    case collections
    /// The bulk-editing table, where the window has a sidebar to hold it.
    case records
}

struct SectionSelector {
    let select: (AppSection) -> Void

    func callAsFunction(_ section: AppSection) {
        select(section)
    }
}
