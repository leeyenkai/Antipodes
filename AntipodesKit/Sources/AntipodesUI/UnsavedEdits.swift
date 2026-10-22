import SwiftUI

/// Where an editing form sits, which decides how the user leaves it without saving.
enum EditorPlacement {
    /// Pushed onto a navigation stack, with a Back button.
    case pushed
    /// The root of a sheet or an inspector, with nothing else to close it.
    case root
    /// Inside a container that has its own Cancel, such as the add sheet.
    case embedded
}

extension EnvironmentValues {
    @Entry var editorPlacement: EditorPlacement = .pushed

    /// Set by a sheet that must close before the add sheet can open over the app: the
    /// request is held, the sheet closes, and the add sheet opens once it has gone.
    /// Unset, a request goes straight to `AppModel.addRequest`.
    @Entry var deferredAdd: DeferredAdd?
}

/// Holds an add request until the sheet it was made in has closed. A struct around the
/// closure, so the environment can tell when it changed.
struct DeferredAdd {
    let id = UUID()
    let perform: (AddRequest) -> Void

    func callAsFunction(_ request: AddRequest) {
        perform(request)
    }
}

/// Whether anything inside has edits that are not saved yet, so a container can ask
/// before throwing them away — a sheet's Cancel, or another pin tapped while the
/// inspector holds a half-edited visit.
struct UnsavedEditsKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// Keeps a form's edits from vanishing without a word.
///
/// Every edit form saves only on its confirm button, so leaving any other way discards.
/// While there are unsaved edits the Back button gives way to Cancel, which asks first,
/// and a sheet cannot be swiped away. With nothing changed, leaving is as quick as ever.
struct UnsavedEditsGuard: ViewModifier {
    let hasChanges: Bool
    let discard: () -> Void

    @Environment(\.editorPlacement) private var placement
    @State private var isConfirming = false

    func body(content: Content) -> some View {
        content
            .preference(key: UnsavedEditsKey.self, value: hasChanges)
            .interactiveDismissDisabled(hasChanges)
            .navigationBarBackButtonHidden(placement == .pushed && hasChanges)
            .toolbar {
                if showsCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        // Always "Cancel": beside the form's own Done, a "Close" read as a
                        // second way to save.
                        Button("Cancel", role: .cancel) {
                            if hasChanges {
                                isConfirming = true
                            } else {
                                discard()
                            }
                        }
                    }
                }
            }
            .confirmationDialog(
                "Discard your changes?",
                isPresented: $isConfirming,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive, action: discard)
                Button("Keep Editing", role: .cancel) {}
            }
    }

    private var showsCancel: Bool {
        switch placement {
        case .pushed: hasChanges
        case .root: true
        case .embedded: false
        }
    }
}

extension View {
    /// Asks before unsaved edits are thrown away; `discard` leaves without saving.
    func guardingUnsavedEdits(_ hasChanges: Bool, discard: @escaping () -> Void) -> some View {
        modifier(UnsavedEditsGuard(hasChanges: hasChanges, discard: discard))
    }
}

/// "Discard your changes?" for a container that is about to replace or close what it
/// holds — the add sheet's Cancel, or the inspector moving to another record.
struct DiscardConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let discard: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Discard your changes?",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive, action: discard)
            Button("Keep Editing", role: .cancel) {}
        }
    }
}

extension View {
    func confirmingDiscard(isPresented: Binding<Bool>, discard: @escaping () -> Void) -> some View {
        modifier(DiscardConfirmation(isPresented: isPresented, discard: discard))
    }
}
