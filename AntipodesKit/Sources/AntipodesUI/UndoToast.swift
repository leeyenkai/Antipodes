import SwiftUI

/// "Deleted Rome · Undo", for a few seconds after anything is deleted — or, with nothing
/// to undo, what just happened: "Added 42 journeys".
///
/// Deleting by swipe asks nothing first — that is what makes it quick — so it has to
/// be reversible instead. The deleted records are put back by the same identity, so a
/// trip gets its places back and a widget's link to a visit still works.
struct UndoToast: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.lastDeletion == nil, let notice = model.notice {
                Label(notice.message, systemImage: notice.systemImage)
                    .lineLimit(2)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 520)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom)
                        .combined(with: .opacity))
                    .task(id: notice.id) {
                        try? await Task.sleep(for: .seconds(4))
                        if model.notice?.id == notice.id {
                            model.notice = nil
                        }
                    }
                    .accessibilityAddTraits(.updatesFrequently)
            } else if let deletion = model.lastDeletion {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                    Text(deletion.message)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button("Undo") { model.undoLastDeletion() }
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 16)
                .frame(maxWidth: 520)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .task(id: deletion.id) {
                    try? await Task.sleep(for: .seconds(6))
                    if model.lastDeletion?.id == deletion.id {
                        model.lastDeletion = nil
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: "Undo") { model.undoLastDeletion() }
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: model.lastDeletion?.id)
        .animation(reduceMotion ? nil : .snappy, value: model.notice?.id)
    }
}
