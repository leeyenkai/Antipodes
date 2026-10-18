import AntipodesCore
import MapKit
import SwiftUI

/// The home screen: where you have been, drawn on a map (§9).
///
/// This is the **basic** globe the first milestone calls for. Whether the shipping
/// version uses MapKit or a custom offline globe is unresolved (Q-3), and MapKit needs
/// network tiles, which sits awkwardly with the offline-first rule. Everything this
/// screen draws comes from the log, so swapping the renderer does not touch the data.
struct GlobeScreen: View {
    @Environment(AppModel.self) private var model
    @State private var selectedYear: Int?

    var body: some View {
        NavigationStack {
            Map {
                ForEach(visitAnnotations, id: \.id) { annotation in
                    Marker(
                        annotation.name,
                        systemImage: annotation.symbol,
                        coordinate: annotation.coordinate
                    )
                    .tint(annotation.tint)
                }
                ForEach(flightArcs, id: \.id) { arc in
                    MapPolyline(coordinates: arc.coordinates)
                        .stroke(.orange.opacity(0.8), lineWidth: 2)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .overlay(alignment: .top) { summaryBar }
            .navigationTitle("Globe")
            .toolbar { yearFilter }
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 16) {
            summaryItem(
                "\(model.statistics.coverage.countriesVisited)",
                label: "countries"
            )
            summaryItem(model.statistics.formattedDistance, label: "travelled")
            summaryItem("\(visitAnnotations.count)", label: "places")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .capsule)
        .padding(.top, 8)
    }

    private func summaryItem(_ value: String, label: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.subheadline.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ToolbarContentBuilder
    private var yearFilter: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Year", selection: $selectedYear) {
                Text("All years").tag(Int?.none)
                ForEach(availableYears, id: \.self) { year in
                    Text(String(year)).tag(Int?.some(year))
                }
            }
        }
    }

    private var availableYears: [Int] {
        Set(model.log.visits.compactMap(\.date.year))
            .union(model.log.allLegs.compactMap(\.date.year))
            .sorted(by: >)
    }

    private func matchesFilter(_ date: FlexibleDate) -> Bool {
        guard let selectedYear else { return true }
        return date.year == selectedYear
    }

    private var visitAnnotations: [VisitAnnotation] {
        model.log.visits.compactMap { visit in
            guard matchesFilter(visit.date),
                  let coordinate = visit.place.coordinate,
                  model.rules.countsTowardsCoverage(visit.visitType)
                  || visit.visitType == .passedThrough || visit.visitType == .layover
            else { return nil }

            return VisitAnnotation(
                id: visit.id,
                name: visit.place.name,
                symbol: visit.place.kind.symbolName,
                coordinate: CLLocationCoordinate2D(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                ),
                tint: model.rules.countsTowardsCoverage(visit.visitType) ? .accentColor : .gray
            )
        }
    }

    /// Flight arcs follow the same great circle the distance is measured along, so the
    /// picture and the number can never disagree (R-PATH-4).
    private var flightArcs: [FlightArc] {
        model.log.allLegs.compactMap { leg in
            guard leg.mode == .flight, matchesFilter(leg.date) else { return nil }
            let path = leg.pathForDisplay(segments: 48)
            guard path.count > 1 else { return nil }
            return FlightArc(
                id: leg.id,
                coordinates: path.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
            )
        }
    }

    private struct VisitAnnotation {
        let id: UUID
        let name: String
        let symbol: String
        let coordinate: CLLocationCoordinate2D
        let tint: Color
    }

    private struct FlightArc {
        let id: UUID
        let coordinates: [CLLocationCoordinate2D]
    }
}
