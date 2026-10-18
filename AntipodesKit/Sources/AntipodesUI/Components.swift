import AntipodesCore
import AntipodesPlaces
import AntipodesStats
import SwiftUI

/// A headline number with its caveat underneath.
///
/// The caveat is part of the card, not a tooltip, because a stat that quietly dropped
/// records is the failure mode this app is trying to avoid (R-CALC-5).
struct StatCard: View {
    let headline: TravelStatistics.Headline

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(headline.value)
                .font(.title2.weight(.semibold))
                .contentTransition(.numericText())
            if let detail = headline.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let caveat = headline.caveat {
                CaveatLabel(text: caveat)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }
}

struct CaveatLabel: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}

struct PlaceResultRow: View {
    let result: PlaceSearchResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.kind.symbolName)
                .frame(width: 24)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let code = result.code {
                Text(code)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
            }
        }
    }
}

/// Picks a date at whatever precision the user actually knows (R-DATE-1).
///
/// Precision is chosen first, deliberately: offering a full day picker to someone who
/// only remembers the year invites them to invent a date.
struct FlexibleDateField: View {
    @Binding var date: FlexibleDate

    @State private var precision: FlexibleDate.Precision = .day
    @State private var day = Date()
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var month = Calendar.current.component(.month, from: Date())

    private static let monthNames = Calendar.current.monthSymbols

    var body: some View {
        Group {
            Picker("How well do you remember it?", selection: $precision) {
                Text("Exact day").tag(FlexibleDate.Precision.day)
                Text("Month").tag(FlexibleDate.Precision.month)
                Text("Year").tag(FlexibleDate.Precision.year)
                Text("Unknown").tag(FlexibleDate.Precision.unknown)
            }
            .pickerStyle(.segmented)

            switch precision {
            case .day, .range:
                DatePicker("Date", selection: $day, displayedComponents: .date)
            case .month:
                Picker("Month", selection: $month) {
                    ForEach(Array(Self.monthNames.enumerated()), id: \.offset) { index, name in
                        Text(name).tag(index + 1)
                    }
                }
                yearStepper
            case .year:
                yearStepper
            case .unknown:
                Text("Stats that need a date will skip this one and say so.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: precision) { _, _ in publish() }
        .onChange(of: day) { _, _ in publish() }
        .onChange(of: month) { _, _ in publish() }
        .onChange(of: year) { _, _ in publish() }
        .onAppear { publish() }
    }

    private var yearStepper: some View {
        Stepper(value: $year, in: 1900 ... 2100) {
            Text("Year: \(String(year))")
        }
    }

    private func publish() {
        switch precision {
        case .day, .range:
            let components = Calendar.current.dateComponents([.year, .month, .day], from: day)
            if let y = components.year, let m = components.month, let d = components.day,
               let calendarDate = CalendarDate(year: y, month: m, day: d) {
                date = .day(calendarDate)
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

extension FlexibleDate {
    /// Human-readable form for lists and detail views.
    var displayText: String {
        switch self {
        case let .day(date):
            date.date()?.formatted(date: .abbreviated, time: .omitted) ?? date.iso
        case let .range(start, end):
            "\(start.iso) – \(end.iso)"
        case let .month(year, month):
            "\(Calendar.current.monthSymbols[max(0, min(11, month - 1))]) \(String(year))"
        case let .year(year):
            String(year)
        case .unknown:
            "Date unknown"
        }
    }
}
