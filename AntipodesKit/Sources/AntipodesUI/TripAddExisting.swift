import AntipodesCore
import SwiftUI

/// Files places and journeys already in the log under a trip, several at once
/// (R-LOG-2, R-MODEL-3). Logging first and grouping later is the usual order — an
/// import, a photo scan, a visit logged on the day — and touching and holding each
/// record to move it was the only way before.
struct AddExistingToTripSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID

    @State private var chosen: Set<Record> = []
    @State private var search = ""

    enum Record: Hashable {
        case visit(UUID)
        case journey(UUID)
    }

    var body: some View {
        NavigationStack {
            List {
                if !unfiledJourneys.isEmpty || !unfiledVisits.isEmpty {
                    Section("Not in a trip") {
                        rows(journeys: unfiledJourneys, visits: unfiledVisits)
                    }
                }
                if !elsewhereJourneys.isEmpty || !elsewhereVisits.isEmpty {
                    Section {
                        rows(journeys: elsewhereJourneys, visits: elsewhereVisits)
                    } header: {
                        Text("In other trips")
                    } footer: {
                        Text("Choosing one of these moves it out of its trip and into this one.")
                    }
                }
            }
            .overlay {
                if isEmpty {
                    if search.trimmingCharacters(in: .whitespaces).isEmpty {
                        ContentUnavailableView(
                            "Nothing else logged",
                            systemImage: "tray",
                            description: Text("Everything in your log is already in this trip.")
                        )
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .searchable(text: $search, prompt: "Places and journeys")
            .navigationTitle("Add to Trip")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(chosen.isEmpty ? "Add" : "Add \(chosen.count)", action: add)
                        .disabled(chosen.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(!chosen.isEmpty)
        #if os(macOS)
            .frame(minWidth: 460, idealWidth: 520, minHeight: 520, idealHeight: 640)
        #endif
    }

    @ViewBuilder
    private func rows(journeys: [Journey], visits: [Visit]) -> some View {
        ForEach(journeys) { journey in
            ChoiceRow(isChosen: chosen.contains(.journey(journey.id))) {
                toggle(.journey(journey.id))
            } label: {
                JourneyRow(journey: journey)
            }
        }
        ForEach(visits) { visit in
            ChoiceRow(isChosen: chosen.contains(.visit(visit.id))) {
                toggle(.visit(visit.id))
            } label: {
                VisitRow(visit: visit)
            }
        }
    }

    private func toggle(_ record: Record) {
        if chosen.contains(record) {
            chosen.remove(record)
        } else {
            chosen.insert(record)
        }
    }

    private func add() {
        let visits = chosen.compactMap {
            if case let .visit(id) = $0 {
                id
            } else {
                nil
            }
        }
        let journeys = chosen.compactMap {
            if case let .journey(id) = $0 {
                id
            } else {
                nil
            }
        }
        if !visits.isEmpty {
            model.moveVisits(visits, toTrip: tripID)
        }
        if !journeys.isEmpty {
            model.moveJourneys(journeys, toTrip: tripID)
        }
        model.announce("Added \(Format.ordinalCount(chosen.count, "record")) to the trip")
        dismiss()
    }

    // MARK: - What can be added

    private var isEmpty: Bool {
        unfiledJourneys.isEmpty && unfiledVisits.isEmpty
            && elsewhereJourneys.isEmpty && elsewhereVisits.isEmpty
    }

    private func matches(_ text: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty || text.lowercased().contains(query)
    }

    /// Newest first: what was just logged is usually what is being filed.
    private var otherVisits: [Visit] {
        model.log.visits
            .filter { $0.tripID != tripID && matches($0.place.name) }
            .sorted { $0.date > $1.date }
    }

    private var otherJourneys: [Journey] {
        model.log.journeys
            .filter { $0.tripID != tripID && matches($0.displayTitle) }
            .sorted { $0.date > $1.date }
    }

    private var unfiledVisits: [Visit] {
        otherVisits.filter { $0.tripID == nil }
    }

    private var unfiledJourneys: [Journey] {
        otherJourneys.filter { $0.tripID == nil }
    }

    private var elsewhereVisits: [Visit] {
        otherVisits.filter { $0.tripID != nil }
    }

    private var elsewhereJourneys: [Journey] {
        otherJourneys.filter { $0.tripID != nil }
    }
}

/// A row that is chosen or not, with a check mark — a plain button, so it works the same
/// with a finger, a pointer and VoiceOver.
private struct ChoiceRow<Label: View>: View {
    let isChosen: Bool
    let toggle: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .accessibilityHidden(true)
                label
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}
