import AntipodesCore
import AntipodesPlaces
import SwiftUI

/// Search the bundled database and pick one place (R-LOG-1). Offline: every query runs
/// against the local SQLite file and never leaves the device (R-PRIV-3).
///
/// Used wherever a place is chosen — the add sheet, both ends of a leg, home, the
/// wishlist and the import review.
struct PlaceSearchList: View {
    @Environment(AppModel.self) private var model

    var prompt: String
    var kinds: [PlaceKind] = [.city, .landmark, .airport]
    /// Restrict to these kinds without offering a scope picker.
    var fixedKinds: Set<PlaceKind>?
    /// Shown while the search field is empty.
    var suggestions: [PlaceReference] = []
    var suggestionsTitle = "Recent"
    /// Other ways in, shown above the suggestions while nothing is typed — reachable
    /// even while the focused search field has hidden the navigation bar.
    var shortcuts: [SearchShortcut] = []
    let onPick: (PlaceSearchResult) -> Void
    var onPickSuggestion: ((PlaceReference) -> Void)?
    /// Offer "Add to Wishlist" on each place, by swipe and context menu (R-WISH-1).
    var offersWishlist = false

    @State private var text = ""
    @FocusState private var isSearchFocused: Bool
    @State private var scope: PlaceKind?
    @State private var results: [PlaceSearchResult] = []
    @State private var isSearching = false

    var body: some View {
        List {
            if let error = model.placesError {
                ContentUnavailableView(
                    "No place database",
                    systemImage: "externaldrive.badge.questionmark",
                    description: Text(error)
                )
            } else if text.trimmingCharacters(in: .whitespaces).isEmpty {
                if !shortcuts.isEmpty {
                    Section {
                        ForEach(shortcuts) { shortcut in
                            Button(action: shortcut.action) {
                                HStack(spacing: 12) {
                                    SymbolTile(systemName: shortcut.symbol, tint: shortcut.tint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(shortcut.title)
                                        Text(shortcut.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !suggestions.isEmpty {
                    Section(suggestionsTitle) {
                        ForEach(suggestions) { place in
                            Button {
                                onPickSuggestion?(place)
                            } label: {
                                PlaceRow(place: place)
                            }
                            .buttonStyle(.plain)
                            .wishlistActions(for: place, isOffered: offersWishlist)
                        }
                    }
                }
            } else if results.isEmpty, !isSearching {
                ContentUnavailableView.search(text: text)
            } else {
                Section {
                    ForEach(results) { result in
                        Button {
                            onPick(result)
                        } label: {
                            PlaceResultRow(result: result)
                        }
                        .buttonStyle(.plain)
                        .wishlistActions(for: result.placeReference, isOffered: offersWishlist)
                    }
                }
            }
        }
        .searchable(text: $text, placement: .navigationBarDrawerAlwaysVisible, prompt: prompt)
        .searchFocused($isSearchFocused)
        // Return takes the top result, as it does in every search field.
        .onSubmit(of: .search) {
            if let first = results.first {
                onPick(first)
            }
        }
        .onAppear {
            // Search-first: the keyboard is up as soon as the sheet is (R-LOG-1).
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                isSearchFocused = true
            }
        }
        .searchScopes($scope, activation: .onSearchPresentation) {
            if fixedKinds == nil {
                Text("All").tag(PlaceKind?.none)
                ForEach(kinds, id: \.self) { kind in
                    Text(kind.pluralName).tag(PlaceKind?.some(kind))
                }
            }
        }
        .task(id: SearchRequest(text: text, scope: scope)) {
            await runSearch()
        }
    }

    private var effectiveKinds: Set<PlaceKind>? {
        if let fixedKinds {
            return fixedKinds
        }
        return scope.map { [$0] }
    }

    private func runSearch() async {
        let query = text
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        isSearching = true
        // Debounce: a keystroke cancels the previous task, so only a pause hits SQLite.
        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else { return }
        results = await model.search(query, kinds: effectiveKinds)
        isSearching = false
    }

    private struct SearchRequest: Equatable {
        let text: String
        let scope: PlaceKind?
    }
}

extension PlaceKind {
    var pluralName: String {
        switch self {
        case .country: "Countries"
        case .region: "Regions"
        case .city: "Cities"
        case .landmark: "Landmarks"
        case .airport: "Airports"
        case .route: "Routes"
        case .custom: "Pins"
        }
    }
}

#if os(macOS)
    extension SearchFieldPlacement {
        static var navigationBarDrawerAlwaysVisible: SearchFieldPlacement {
            .automatic
        }
    }
#else
    extension SearchFieldPlacement {
        static var navigationBarDrawerAlwaysVisible: SearchFieldPlacement {
            .navigationBarDrawer(displayMode: .always)
        }
    }
#endif

/// A sheet that picks one place and dismisses.
struct PlacePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var prompt = "Search places"
    var kinds: [PlaceKind] = [.country, .city, .landmark, .airport]
    var fixedKinds: Set<PlaceKind>?
    var suggestions: [PlaceReference] = []
    let onPick: (PlaceReference) -> Void

    var body: some View {
        NavigationStack {
            PlaceSearchList(
                prompt: prompt,
                kinds: kinds,
                fixedKinds: fixedKinds,
                suggestions: suggestions,
                onPick: { result in
                    onPick(result.placeReference)
                    dismiss()
                },
                onPickSuggestion: { place in
                    onPick(place)
                    dismiss()
                }
            )
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
    }
}

/// A non-search way into logging, offered beside the search results.
struct SearchShortcut: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let action: () -> Void
}

extension View {
    /// "Add to Wishlist" for one place, as a leading swipe and in the context menu, with
    /// a tap of feedback as it lands (R-WISH-1). Routes are wishlisted from their own
    /// page, which knows the whole route.
    func wishlistActions(for place: PlaceReference, isOffered: Bool) -> some View {
        modifier(WishlistActions(place: place, isOffered: isOffered && place.kind != .route))
    }
}

private struct WishlistActions: ViewModifier {
    @Environment(AppModel.self) private var model
    let place: PlaceReference
    let isOffered: Bool
    @State private var toggled = 0

    func body(content: Content) -> some View {
        if isOffered {
            let isOn = model.isOnWishlist(place)
            content
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button(
                        isOn ? "Remove from Wishlist" : "Wishlist",
                        systemImage: isOn ? "star.slash" : "star"
                    ) {
                        toggle()
                    }
                    .tint(Palette.wishlist)
                }
                .contextMenu {
                    Button(
                        isOn ? "Remove from Wishlist" : "Add to Wishlist",
                        systemImage: isOn ? "star.slash" : "star"
                    ) { toggle() }
                }
                // A small star on the corner of the row's icon, clear of an airport's code
                // at the other end.
                .overlay(alignment: .topLeading) {
                    if isOn {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.wishlist)
                            .shadow(color: .black.opacity(0.4), radius: 1)
                            .offset(x: 24, y: -3)
                            .accessibilityLabel("On your wishlist")
                    }
                }
                .sensoryFeedback(.selection, trigger: toggled)
        } else {
            content
        }
    }

    private func toggle() {
        model.toggleWishlist(place)
        toggled += 1
    }
}
