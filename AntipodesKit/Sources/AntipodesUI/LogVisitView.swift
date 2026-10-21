import AntipodesCore
import AntipodesPlaces
import SwiftUI

/// Logs or edits one visit: type, date, trip, rating, notes. Everything has a default,
/// so a new visit can be saved straight away — search, tap the place, tap Save
/// (R-LOG-3, M1 acceptance criterion 2).
struct VisitForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.deferredAdd) private var deferredAdd

    let place: PlaceReference
    /// The visit being edited, or `nil` for a new one.
    let existing: Visit?
    let onDone: () -> Void

    @State private var name: String
    @State private var visitType: VisitType
    @State private var date: FlexibleDate
    @State private var tripID: UUID?
    @State private var rating: Int?
    @State private var notes: String
    @State private var isConfirmingDelete = false
    @State private var saved = false
    /// What the form held when it opened, so it knows whether there is anything to lose.
    @State private var baseline: Fields

    /// Everything the user can change here, for comparing against `baseline`.
    struct Fields: Equatable {
        var name: String
        var visitType: VisitType
        var date: FlexibleDate
        var tripID: UUID?
        var rating: Int?
        var notes: String
    }

    private var fields: Fields {
        Fields(
            name: name,
            visitType: visitType,
            date: date,
            tripID: tripID,
            rating: rating,
            notes: notes
        )
    }

    init(
        place: PlaceReference,
        existing: Visit? = nil,
        tripID: UUID? = nil,
        onDone: @escaping () -> Void
    ) {
        self.place = place
        self.existing = existing
        self.onDone = onDone
        _name = State(initialValue: existing?.place.name ?? place.name)
        _visitType = State(initialValue: existing?.visitType ?? .stayed)
        _date = State(initialValue: existing?.date ?? .day(.today()))
        _tripID = State(initialValue: existing?.tripID ?? tripID)
        _rating = State(initialValue: existing?.rating)
        _notes = State(initialValue: existing?.notes ?? "")
        _baseline = State(initialValue: Fields(
            name: existing?.place.name ?? place.name,
            visitType: existing?.visitType ?? .stayed,
            date: existing?.date ?? .day(.today()),
            tripID: existing?.tripID ?? tripID,
            rating: existing?.rating,
            notes: existing?.notes ?? ""
        ))
    }

    var body: some View {
        Form {
            Section {
                PlaceHeader(place: place)
                if place.kind == .custom {
                    TextField("Name", text: $name)
                        .capitalizingWords()
                }
            }

            Section {
                Picker("Visit type", selection: $visitType) {
                    ForEach(VisitType.allCases) { type in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(type.displayName)
                                Text(type.explanation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: type.symbolName)
                        }
                        .tag(type)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("How did you visit?")
            } footer: {
                if !model.rules.countsTowardsCoverage(visitType) {
                    Text("""
                    \(visitType.displayName) doesn't count towards coverage under your \
                    current rules, so it won't shade the globe. You can change that in \
                    Settings.
                    """)
                }
            }

            Section("When") {
                FlexibleDateField(date: $date)
            }

            Section("Trip") {
                TripPicker(selection: $tripID)
            }

            Section("Notes") {
                RatingPicker(rating: $rating)
                TextField("What do you want to remember?", text: $notes, axis: .vertical)
                    .lineLimit(2 ... 8)
            }

            if let existing {
                Section {
                    Button("Log Another Visit Here", systemImage: "arrow.clockwise") {
                        let request = AddRequest(
                            start: .place(existing.place),
                            tripID: existing.tripID
                        )
                        if let deferredAdd {
                            deferredAdd(request)
                        } else {
                            model.addRequest = request
                        }
                    }
                    Button("Delete Visit", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
        }
        .navigationTitle(existing == nil ? "Log Visit" : "Edit Visit")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(existing == nil ? "Save" : "Done", systemImage: "checkmark", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .guardingUnsavedEdits(fields != baseline && !saved, discard: onDone)
        .sensoryFeedback(.success, trigger: saved)
        .confirmationDialog(
            "Delete this visit?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Visit", role: .destructive) {
                if let existing {
                    model.deleteVisits([existing.id])
                }
                onDone()
            }
        } message: {
            Text(
                "It is removed from your log and every statistic."
                    + " You can undo it straight afterwards."
            )
        }
    }

    private func save() {
        var finalPlace = existing?.place ?? place
        if finalPlace.kind == .custom {
            finalPlace.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if var visit = existing {
            visit.place = finalPlace
            visit.visitType = visitType
            visit.date = date
            visit.tripID = tripID
            visit.rating = rating
            visit.notes = notes.trimmedOrNil
            // A failed save keeps the form open with the edits in it; the app-wide
            // alert says what went wrong.
            guard model.updateVisit(visit) else { return }
            saved = true
            onDone()
            return
        }
        do {
            try model.logVisit(
                place: finalPlace,
                visitType: visitType,
                date: date,
                tripID: tripID,
                rating: rating,
                notes: notes
            )
            saved = true
            onDone()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

/// A place's identity at the top of a form: icon, name, where it is, and its flag.
struct PlaceHeader: View {
    let place: PlaceReference

    var body: some View {
        HStack(spacing: 14) {
            SymbolTile(systemName: place.kind.symbolName, tint: place.kind.tint, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(.title3.weight(.semibold))
                Text(place.contextLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let coordinate = place.coordinate {
                    Text(coordinate.displayText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            Text(place.flag)
                .font(.largeTitle)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

extension Coordinate {
    /// "59.914° N, 10.752° E".
    var displayText: String {
        let lat = abs(latitude).formatted(.number.precision(.fractionLength(3)))
        let lon = abs(longitude).formatted(.number.precision(.fractionLength(3)))
        return "\(lat)° \(latitude >= 0 ? "N" : "S"), \(lon)° \(longitude >= 0 ? "E" : "W")"
    }
}
