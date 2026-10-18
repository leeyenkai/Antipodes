import AntipodesCore
import AntipodesPlaces
import SwiftUI

/// Search first, then confirm (§9, R-LOG-1).
///
/// The target is four taps from the add button to a logged visit (R-JLOG-1), which is
/// why search opens focused and the date and visit type default to something sensible
/// rather than demanding input.
struct AddSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var entry: Entry = .place
    @State private var searchText = ""
    @State private var results: [PlaceSearchResult] = []
    @State private var kindFilter: PlaceKind?
    @State private var isSearching = false

    @State private var chosenPlace: PlaceSearchResult?
    @State private var flightOrigin: PlaceSearchResult?
    @State private var flightDestination: PlaceSearchResult?

    enum Entry: String, CaseIterable, Identifiable {
        case place
        case flight

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .place: "Place"
            case .flight: "Flight"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let error = model.placesError {
                    DatabaseMissingView(message: error)
                } else {
                    searchList
                }
            }
            .navigationTitle("Log")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(item: $chosenPlace) { result in
                LogVisitView(result: result) { dismiss() }
            }
            .navigationDestination(item: $flightDestination) { destination in
                if let origin = flightOrigin {
                    LogFlightView(origin: origin, destination: destination) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var searchList: some View {
        List {
            Section {
                Picker("What are you logging?", selection: $entry) {
                    ForEach(Entry.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if entry == .flight {
                    FlightLegPrompt(origin: flightOrigin) { flightOrigin = nil }
                }
            }

            if !results.isEmpty {
                Section(resultsHeader) {
                    ForEach(results) { result in
                        Button {
                            choose(result)
                        } label: {
                            PlaceResultRow(result: result)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if !searchText.isEmpty, !isSearching {
                Section {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .searchable(text: $searchText, prompt: searchPrompt)
        .searchScopes($kindFilter) {
            Text("All").tag(PlaceKind?.none)
            ForEach(scopeKinds, id: \.self) { kind in
                Text(kind.displayName).tag(PlaceKind?.some(kind))
            }
        }
        .task(id: SearchRequest(text: searchText, kind: kindFilter, entry: entry)) {
            await runSearch()
        }
    }

    private var scopeKinds: [PlaceKind] {
        entry == .flight ? [.airport] : [.country, .city, .landmark, .airport]
    }

    private var searchPrompt: String {
        switch entry {
        case .place: "Countries, cities, landmarks, airports"
        case .flight: flightOrigin == nil ? "Departure airport" : "Arrival airport"
        }
    }

    private var resultsHeader: String {
        isSearching ? "Searching…" : "Results"
    }

    /// Flights only ever search airports, so the user does not have to filter by hand.
    private var effectiveKinds: Set<PlaceKind>? {
        if entry == .flight {
            return [.airport]
        }
        if let kindFilter {
            return [kindFilter]
        }
        return nil
    }

    private func runSearch() async {
        let text = searchText
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        isSearching = true
        // Debounce: a keystroke cancels the previous task, so only a pause hits SQLite.
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        results = await model.search(text, kinds: effectiveKinds)
        isSearching = false
    }

    private func choose(_ result: PlaceSearchResult) {
        switch entry {
        case .place:
            chosenPlace = result
        case .flight:
            if flightOrigin == nil {
                flightOrigin = result
                searchText = ""
                results = []
            } else {
                flightDestination = result
            }
        }
    }

    /// One identity for "what should be searched", so `.task(id:)` reruns on any
    /// change without four separate observers.
    private struct SearchRequest: Equatable {
        let text: String
        let kind: PlaceKind?
        let entry: Entry
    }
}

private struct FlightLegPrompt: View {
    let origin: PlaceSearchResult?
    let clear: () -> Void

    var body: some View {
        if let origin {
            HStack {
                Label("From \(origin.name)", systemImage: "airplane.departure")
                Spacer()
                Button("Change", action: clear)
                    .buttonStyle(.borderless)
            }
            .font(.callout)
        } else {
            Label("Search the departure airport", systemImage: "airplane.departure")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DatabaseMissingView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("No place database", systemImage: "externaldrive.badge.questionmark")
        } description: {
            Text(message)
        }
    }
}
