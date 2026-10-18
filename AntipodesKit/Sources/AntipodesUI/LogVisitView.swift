import AntipodesCore
import AntipodesPlaces
import SwiftUI

/// Confirms a visit: type, date, trip. Everything here has a default, so the user can
/// tap Save straight away (R-JLOG-1).
struct LogVisitView: View {
    @Environment(AppModel.self) private var model

    let result: PlaceSearchResult
    let onSaved: () -> Void

    @State private var visitType: VisitType = .stayed
    @State private var date: FlexibleDate = .unknown
    @State private var tripID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                PlaceResultRow(result: result)
            }

            Section("How did you visit?") {
                Picker("Visit type", selection: $visitType) {
                    ForEach(VisitType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                if !model.rules.countsTowardsCoverage(visitType) {
                    CaveatLabel(
                        text: """
                        \(visitType.displayName) does not count towards coverage under \
                        your current rules. You can change that in Settings.
                        """
                    )
                }
            }

            Section("When?") {
                FlexibleDateField(date: $date)
            }

            Section("Trip") {
                TripPicker(selection: $tripID)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(result.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
    }

    private func save() {
        do {
            try model.logVisit(
                place: result.placeReference,
                visitType: visitType,
                date: date,
                tripID: tripID
            )
            onSaved()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

/// Confirms a flight leg. Distance is shown before saving, computed from the same
/// great circle the globe draws (R-PATH-4).
struct LogFlightView: View {
    @Environment(AppModel.self) private var model

    let origin: PlaceSearchResult
    let destination: PlaceSearchResult
    let onSaved: () -> Void

    @State private var date: FlexibleDate = .unknown
    @State private var airline = ""
    @State private var flightNumber = ""
    @State private var tripID: UUID?
    @State private var errorMessage: String?

    private var distanceKm: Double? {
        guard let from = origin.coordinate, let to = destination.coordinate else { return nil }
        return GreatCircle.distanceKm(from: from, to: to)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("From", value: "\(origin.code ?? "—") · \(origin.name)")
                LabeledContent("To", value: "\(destination.code ?? "—") · \(destination.name)")
                if let distanceKm {
                    LabeledContent("Distance") {
                        Text(formatted(distanceKm))
                    }
                } else {
                    CaveatLabel(
                        text: """
                        One of these airports has no coordinate, so this leg has no \
                        distance.
                        """
                    )
                }
            }

            Section("When?") {
                FlexibleDateField(date: $date)
            }

            Section("Detail (optional)") {
                TextField("Airline", text: $airline)
                TextField("Flight number", text: $flightNumber)
            }

            Section("Trip") {
                TripPicker(selection: $tripID)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Flight")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
    }

    private func formatted(_ kilometres: Double) -> String {
        let value = model.rules.unitSystem.distance(fromKilometres: kilometres)
        return "\(Int(value.rounded())) \(model.rules.unitSystem.distanceUnitAbbreviation)"
    }

    private func save() {
        do {
            try model.logFlight(
                from: origin.placeReference,
                to: destination.placeReference,
                date: date,
                airline: airline,
                flightNumber: flightNumber,
                tripID: tripID
            )
            onSaved()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

/// Assigning a trip is optional — a visit can stand alone and be filed later
/// (R-MODEL-3).
struct TripPicker: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: UUID?
    @State private var newTripName = ""

    var body: some View {
        Picker("Trip", selection: $selection) {
            Text("No trip").tag(UUID?.none)
            ForEach(model.log.trips, id: \.id) { trip in
                Text(trip.name ?? "Untitled trip").tag(UUID?.some(trip.id))
            }
        }

        HStack {
            TextField("New trip name", text: $newTripName)
            Button("Add") {
                guard !newTripName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                selection = try? model.createTrip(name: newTripName).id
                newTripName = ""
            }
            .disabled(newTripName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
