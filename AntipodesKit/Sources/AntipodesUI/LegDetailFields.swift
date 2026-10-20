import AntipodesCore
import SwiftUI

/// Everything optional about a leg (§5.2), shown when the user expands it (R-LEG-2).
struct LegDetailFields: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: LegDraft

    var body: some View {
        Picker("Purpose", selection: $draft.purpose) {
            ForEach(TripPurpose.allCases) { Text($0.displayName).tag($0) }
        }

        if draft.mode.isScheduledService {
            TextField("Operator", text: $draft.operatorName)
            if let label = draft.mode.serviceNumberLabel {
                TextField(label, text: $draft.serviceNumber)
                    .capitalizingCharacters()
            }
        }

        timesGroup

        TextField(draft.mode.vehicleLabel, text: $draft.vehicle)
        if draft.mode == .flight || draft.mode == .ferry {
            TextField(
                draft.mode == .flight ? "Registration" : "Ship name",
                text: $draft.registration
            )
            .capitalizingCharacters()
        }

        if !draft.mode.classOptions.isEmpty {
            LabeledContent("Class") {
                Menu {
                    ForEach(draft.mode.classOptions, id: \.self) { option in
                        Button(option) { draft.travelClass = option }
                    }
                    if !draft.travelClass.isEmpty {
                        Divider()
                        Button("Clear", role: .destructive) { draft.travelClass = "" }
                    }
                } label: {
                    Text(draft.travelClass.isEmpty ? "Choose" : draft.travelClass)
                }
            }
        }
        if draft.mode.isScheduledService {
            TextField("Seat, carriage or cabin", text: $draft.seat)
        }

        RatingPicker(rating: $draft.rating)
        TextField("Notes", text: $draft.notes, axis: .vertical)
            .lineLimit(1 ... 6)

        DistanceOverrideField(kilometres: $draft.distanceOverrideKm, system: model.rules.unitSystem)
        DurationOverrideRow(minutes: $draft.durationOverrideMinutes)
    }

    @ViewBuilder
    private var timesGroup: some View {
        OptionalTimeRow(
            title: "Departs",
            time: $draft.times.scheduledDeparture,
            defaultDay: draft.date.earliestDay,
            zone: draft.origin?.timeZoneIdentifier
        )
        OptionalTimeRow(
            title: "Arrives",
            time: $draft.times.scheduledArrival,
            defaultDay: draft.date.latestDay,
            zone: draft.destination?.timeZoneIdentifier
        )
        if draft.mode.isScheduledService {
            OptionalTimeRow(
                title: "Actually departed",
                time: $draft.times.actualDeparture,
                defaultDay: draft.times.scheduledDeparture?.date ?? draft.date.earliestDay,
                zone: draft.origin?.timeZoneIdentifier
            )
            OptionalTimeRow(
                title: "Actually arrived",
                time: $draft.times.actualArrival,
                defaultDay: draft.times.scheduledArrival?.date ?? draft.date.latestDay,
                zone: draft.destination?.timeZoneIdentifier
            )
            if let delay = draft.times.arrivalDelayMinutes {
                LabeledContent("Arrival", value: Format.delay(minutes: Double(delay)))
            }
        }
    }
}

/// A time that is either not set, or set to a wall-clock time on a day. Times are local
/// to the station they belong to, as printed on the ticket (§5.2).
private struct OptionalTimeRow: View {
    let title: String
    @Binding var time: LocalDateTime?
    let defaultDay: CalendarDate?
    let zone: String?

    var body: some View {
        if let time {
            HStack {
                DatePicker(
                    title,
                    selection: Binding(
                        get: { time.pickerDate },
                        set: { self.time = LocalDateTime(pickerDate: $0) }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                Button {
                    self.time = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear \(title.lowercased())")
            }
            if let zone {
                Text("Local time in \(zone.replacingOccurrences(of: "_", with: " "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Button {
                let day = defaultDay ?? .today()
                time = LocalDateTime(date: day, hour: 12, minute: 0)
            } label: {
                LabeledContent(title) {
                    Text("Add").foregroundStyle(.tint)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

/// The user's own distance, typed in their units and stored in kilometres.
///
/// The text is the user's while they type: it is parsed, never rewritten, so "2." can
/// become "2.5". Only a number above zero becomes an override; an empty field clears it.
private struct DistanceOverrideField: View {
    @Binding var kilometres: Double?
    let system: UnitSystem
    @State private var text: String

    init(kilometres: Binding<Double?>, system: UnitSystem) {
        _kilometres = kilometres
        self.system = system
        _text = State(initialValue: kilometres.wrappedValue.map {
            system.distance(fromKilometres: $0)
                .formatted(.number.precision(.fractionLength(0 ... 2)).grouping(.never))
        } ?? "")
    }

    var body: some View {
        LabeledContent("Distance (\(system.distanceUnitAbbreviation))") {
            TextField("Calculated", text: $text)
                .multilineTextAlignment(.trailing)
                .decimalKeyboard()
                .onChange(of: text) { _, new in
                    let trimmed = new.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        kilometres = nil
                    } else if let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")),
                              value > 0 {
                        kilometres = system == .metric ? value : value * 1.609_344
                    }
                }
        }
    }
}

/// The user's own duration, in hours and minutes, which wins over the times.
private struct DurationOverrideRow: View {
    @Binding var minutes: Int?

    var body: some View {
        if let minutes {
            // Hours and minutes as two menus: a stepper took a hundred taps to reach a
            // long-haul flight.
            LabeledContent("Duration") {
                HStack(spacing: 4) {
                    Picker("Hours", selection: Binding(
                        get: { minutes / 60 },
                        set: { self.minutes = $0 * 60 + minutes % 60 }
                    )) {
                        ForEach(0 ... 99, id: \.self) { Text("\($0) h").tag($0) }
                    }
                    Picker("Minutes", selection: Binding(
                        get: { minutes % 60 / 5 * 5 },
                        set: { self.minutes = minutes / 60 * 60 + $0 }
                    )) {
                        ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) {
                            Text("\($0) min").tag($0)
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            Button("Clear duration", role: .destructive) { self.minutes = nil }
                .font(.footnote)
        } else {
            Button {
                minutes = 60
            } label: {
                LabeledContent("Duration") {
                    Text("Enter").foregroundStyle(.tint)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
