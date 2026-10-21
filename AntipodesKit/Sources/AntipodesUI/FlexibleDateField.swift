import AntipodesCore
import SwiftUI

/// Picks a date at whatever precision the user actually knows (R-DATE-1).
///
/// Precision is chosen first, deliberately: offering a full day picker to someone who
/// only remembers the year invites them to invent a date.
struct FlexibleDateField: View {
    @Binding var date: FlexibleDate

    @State private var precision: FlexibleDate.Precision = .day
    @State private var day = Date()
    @State private var endDay = Date()
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var month = Calendar.current.component(.month, from: Date())
    @State private var hasLoaded = false

    var body: some View {
        Group {
            Picker("Precision", selection: $precision) {
                Text("Day").tag(FlexibleDate.Precision.day)
                Text("Range").tag(FlexibleDate.Precision.range)
                Text("Month").tag(FlexibleDate.Precision.month)
                Text("Year").tag(FlexibleDate.Precision.year)
                Text("Unknown").tag(FlexibleDate.Precision.unknown)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch precision {
            case .day:
                DatePicker(
                    "Date",
                    selection: $day,
                    in: ...Date.distantFuture,
                    displayedComponents: .date
                )
            case .range:
                DatePicker("From", selection: $day, displayedComponents: .date)
                DatePicker("To", selection: $endDay, in: day..., displayedComponents: .date)
            case .month:
                Picker("Month", selection: $month) {
                    ForEach(1 ... 12, id: \.self) { Text(Format.monthName($0)).tag($0) }
                }
                yearStepper
            case .year:
                yearStepper
            case .unknown:
                Text("Stats that need a date will skip this one, and say so.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: precision) { publish() }
        .onChange(of: day) {
            if endDay < day {
                endDay = day
            }
            publish()
        }
        .onChange(of: endDay) { publish() }
        .onChange(of: month) { publish() }
        .onChange(of: year) { publish() }
        .onAppear(perform: load)
    }

    private var yearStepper: some View {
        Stepper(value: $year, in: 1900 ... 2100) {
            LabeledContent("Year", value: String(year))
        }
    }

    /// Starts the controls from the date being edited, so editing a visit dated
    /// "June 2019" opens on June 2019 rather than resetting it to today.
    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        precision = date.precision
        switch date {
        case let .day(value):
            day = value.date(in: .current) ?? Date()
        case let .range(start, end):
            day = start.date(in: .current) ?? Date()
            endDay = end.date(in: .current) ?? day
        case let .month(y, m):
            year = y
            month = m
        case let .year(y):
            year = y
        case .unknown:
            break
        }
        publish()
    }

    private func publish() {
        guard hasLoaded else { return }
        switch precision {
        case .day:
            if let value = CalendarDate(day) {
                date = .day(value)
            }
        case .range:
            if let start = CalendarDate(day), let end = CalendarDate(endDay) {
                date = start == end ? .day(start) : .span(start, end)
            }
        case .month:
            date = FlexibleDate.month(year, month) ?? .year(year)
        case .year:
            date = .year(year)
        case .unknown:
            date = .unknown
        }
    }
}
