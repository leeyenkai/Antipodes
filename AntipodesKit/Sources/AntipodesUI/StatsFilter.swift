import AntipodesCore
import SwiftUI

/// Year, trip, mode and purpose filters for the Stats screen (§5.7).
struct StatsFilterMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Menu {
            Picker("Year", selection: $model.statsFilter.year) {
                Text("All years").tag(Int?.none)
                ForEach(years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
            }
            .pickerStyle(.menu)
            if !model.log.trips.isEmpty {
                Picker("Trip", selection: $model.statsFilter.tripID) {
                    Text("All trips").tag(UUID?.none)
                    ForEach(model.tripsNewestFirst) { trip in
                        Text(trip.displayName(model: model)).tag(UUID?.some(trip.id))
                    }
                }
                .pickerStyle(.menu)
            }
            if !modes.isEmpty {
                Picker("Mode", selection: $model.statsFilter.mode) {
                    Text("All modes").tag(TravelMode?.none)
                    ForEach(modes) { mode in
                        Label(mode.displayName, systemImage: mode.symbolName)
                            .tag(TravelMode?.some(mode))
                    }
                }
                .pickerStyle(.menu)
            }
            Picker("Purpose", selection: $model.statsFilter.purpose) {
                Text("Any purpose").tag(TripPurpose?.none)
                ForEach(TripPurpose.allCases) { Text($0.displayName).tag(TripPurpose?.some($0)) }
            }
            .pickerStyle(.menu)
            if model.statsFilter.isActive {
                Divider()
                Button("Clear Filters", systemImage: "xmark.circle") {
                    model.statsFilter = .none
                }
            }
        } label: {
            Label(
                "Filter",
                systemImage: model.statsFilter.isActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
    }

    private var years: [Int] {
        Set(model.log.visits.compactMap(\.date.year))
            .union(model.log.allLegs.compactMap(\.date.year))
            .sorted(by: >)
    }

    private var modes: [TravelMode] {
        TravelMode.allCases.filter { mode in model.log.allLegs.contains { $0.mode == mode } }
    }
}

/// What the screen is showing while filtered, with a way back to everything.
struct StatsFilterBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary)
                    .font(.subheadline.weight(.medium))
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Clear") { model.statsFilter = .none }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }

    /// "2023 · Fjords · Rail · Work".
    private var summary: String {
        let filter = model.statsFilter
        return [
            filter.year.map(String.init),
            filter.tripID.flatMap { model.log.trip(id: $0) }.map { $0.displayName(model: model) },
            filter.mode?.displayName,
            filter.purpose?.displayName,
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }

    private var note: String {
        let filter = model.statsFilter
        if filter.mode != nil || filter.purpose != nil {
            return "Journeys only: a mode or purpose belongs to legs, not to places."
        }
        return "Every figure below is for this slice of your log."
    }
}
