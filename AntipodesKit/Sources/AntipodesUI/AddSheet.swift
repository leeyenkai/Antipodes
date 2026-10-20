import AntipodesCore
import AntipodesPlaces
import SwiftUI

/// Search first, then confirm (§9, R-LOG-1).
///
/// Three ways in: search the bundled database for a place or a catalogue route, build a
/// journey leg by leg, or drop a pin for anywhere else. The search field opens focused
/// and everything after has a default, so a visit is four taps away (M1 acceptance
/// criterion 2).
struct AddSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let request: AddRequest

    @State private var entry: Entry
    @State private var path: [Destination]
    /// Whether the journey being built here has anything in it to lose.
    @State private var hasEdits = false
    @State private var isConfirmingCancel = false

    enum Entry: String, CaseIterable, Identifiable {
        case place
        case journey
        case pin

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .place: "Place"
            case .journey: "Journey"
            case .pin: "Pin"
            }
        }
    }

    enum Destination: Hashable {
        case visit(PlaceReference)
        case route(RouteInfo)
    }

    init(request: AddRequest) {
        self.request = request
        var entry = Entry.place
        var path: [Destination] = []
        switch request.start {
        case .search: break
        case .journey: entry = .journey
        case let .route(route): path = [.route(route)]
        case .pin: entry = .pin
        case let .place(place): path = [.visit(place)]
        }
        _entry = State(initialValue: entry)
        _path = State(initialValue: path)
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .environment(\.editorPlacement, .embedded)
                .onPreferenceChange(UnsavedEditsKey.self) { hasEdits = $0 }
                .navigationTitle("Log")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) {
                            if hasEdits {
                                isConfirmingCancel = true
                            } else {
                                dismiss()
                            }
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        Picker("What are you logging?", selection: $entry) {
                            ForEach(Entry.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 280)
                    }
                }
                .navigationDestination(for: Destination.self) { destination in
                    switch destination {
                    case let .visit(place):
                        VisitForm(place: place, tripID: request.tripID) { dismiss() }
                    case let .route(route):
                        JourneyEditor(start: .route(route), tripID: request.tripID) { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
        .confirmingDiscard(isPresented: $isConfirmingCancel) { dismiss() }
    }

    @ViewBuilder
    private var content: some View {
        switch entry {
        case .place:
            PlaceSearchList(
                prompt: "Places, airports and famous routes",
                kinds: [.city, .landmark, .airport],
                suggestions: recentPlaces,
                suggestionsTitle: "Log again",
                shortcuts: [
                    SearchShortcut(
                        id: "journey",
                        title: "Log a Journey",
                        subtitle: "A flight, train, ferry, drive or walk",
                        symbol: "airplane",
                        tint: Palette.mode(.flight),
                        action: { entry = .journey }
                    ),
                    SearchShortcut(
                        id: "pin",
                        title: "Drop a Pin",
                        subtitle: "Anywhere that isn't in the search",
                        symbol: "mappin.and.ellipse",
                        tint: PlaceKind.custom.tint,
                        action: { entry = .pin }
                    ),
                ],
                onPick: pick,
                onPickSuggestion: { path.append(.visit($0)) }
            )
        case .journey:
            JourneyEditor(start: request.start.journeyStart, tripID: request.tripID) { dismiss() }
        case .pin:
            PinDropView(initial: request.start.pinCoordinate ?? model.home?.coordinate) { place in
                path.append(.visit(place))
            }
        }
    }

    private func pick(_ result: PlaceSearchResult) {
        if result.kind == .route, case let .database(_, row) = result.id,
           let route = model.route(id: row) {
            path.append(.route(route))
        } else {
            path.append(.visit(result.placeReference))
        }
    }

    /// The places most recently logged, each once — the fastest way to log a return
    /// visit.
    private var recentPlaces: [PlaceReference] {
        var seen: Set<PlaceID> = []
        return model.log.visits
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            .map(\.place)
            .filter { seen.insert($0.id).inserted }
            .prefix(8)
            .map(\.self)
    }
}

extension AddRequest.Start {
    var journeyStart: AddRequest.Start {
        if case .journey = self {
            return self
        }
        return .journey(nil)
    }

    var pinCoordinate: Coordinate? {
        if case let .pin(coordinate) = self {
            return coordinate
        }
        return nil
    }
}
