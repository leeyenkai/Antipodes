import AntipodesCore
import AntipodesImport
import AntipodesStore
import SwiftUI
#if os(iOS)
    import UIKit
#endif
import UniformTypeIdentifiers
#if canImport(Photos)
    import Photos
#endif

/// Suggests visits from where and when photos were taken (R-LOG-7, R-PRIV-4).
///
/// Opt-in: nothing is read until the user starts it, and the system's limited-library
/// choice is respected — only the photos the user allowed are read. Only each photo's
/// date and location are read, on the device, and nothing about a photo is stored: a
/// confirmed suggestion becomes an ordinary visit (decision D-17, Q-9).
struct PhotoImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var state: LoadState = .idle
    @State private var suggestions: [VisitSuggestion] = []
    @State private var selected: Set<String> = []
    @State private var tripID: UUID?
    @State private var newTripName: String?
    @State private var scanTask: Task<Void, Never>?
    @State private var isConfirmingCancel = false

    enum LoadState: Equatable {
        case idle
        case reading(String)
        case denied
        case done
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .idle:
                    EmptyStateView(
                        title: "Find visits in your photos",
                        message: """
                        Antipodes reads the date and location of your photos on this device \
                        and suggests visits for you to confirm. Nothing is uploaded and no \
                        photo is copied.
                        """,
                        systemImage: "photo.on.rectangle.angled",
                        actionTitle: "Allow Access and Scan",
                        action: { scanTask = Task { await scan() } }
                    )
                case let .reading(progress):
                    ProgressView(progress)
                case .denied:
                    EmptyStateView(
                        title: "No access to Photos",
                        message: """
                        Allow Antipodes to read your photos in \(Self.settingsName), or \
                        choose selected photos only.
                        """,
                        systemImage: "lock",
                        actionTitle: "Open \(Self.settingsName)",
                        action: openPrivacySettings
                    )
                case .done:
                    review
                }
            }
            .interactiveDismissDisabled(hasReview)
            .navigationTitle("Import from Photos")
            .toolbarTitleDisplayMode(.inline)
            // Closing the sheet stops a scan of a large library rather than letting it
            // run on, unseen, to the end.
            .onDisappear { scanTask?.cancel() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        if hasReview {
                            isConfirmingCancel = true
                        } else {
                            dismiss()
                        }
                    }
                    .confirmingDiscard(isPresented: $isConfirmingCancel) { dismiss() }
                }
                if state == .done {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add \(selected.count)") { importSelected() }
                            .disabled(selected.isEmpty)
                    }
                }
            }
        }
    }

    private var review: some View {
        List {
            if suggestions.isEmpty {
                ContentUnavailableView(
                    "No new places",
                    systemImage: "checkmark.circle",
                    description: Text("Every place in your photos is already logged, or at home.")
                )
            } else {
                Section {
                    TripPicker(selection: $tripID, newTripName: $newTripName)
                    Button(selected.count == fresh.count ? "Deselect All" : "Select All") {
                        selected = selected.count == fresh.count ? [] : Set(fresh.map(\.id))
                    }
                }
                Section("\(suggestions.count) suggested visits") {
                    ForEach(suggestions) { suggestion in
                        Button {
                            if selected.contains(suggestion.id) {
                                selected.remove(suggestion.id)
                            } else {
                                selected.insert(suggestion.id)
                            }
                        } label: {
                            HStack {
                                Image(systemName: selected
                                    .contains(suggestion.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(
                                        selected.contains(suggestion.id) ? Palette
                                            .visited : .secondary
                                    )
                                    .font(.title3)
                                PlaceRow(
                                    place: suggestion.place,
                                    subtitle: ([
                                        suggestion.date.displayText,
                                        Format.ordinalCount(suggestion.photoCount, "photo"),
                                        suggestion.alreadyLogged ? "already logged" : nil,
                                    ] as [String?]).compactMap(\.self).joined(separator: " · ")
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected.contains(suggestion.id) ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var fresh: [VisitSuggestion] {
        suggestions.filter { !$0.alreadyLogged }
    }

    private func scan() async {
        #if canImport(Photos)
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard status == .authorized || status == .limited else {
                state = .denied
                return
            }
            state = .reading("Reading photo locations…")
            let samples = await Task.detached(priority: .userInitiated) { Self.samples() }.value

            // Photos taken close together share a city lookup: rounding to a hundredth
            // of a degree (about a kilometre) keeps the database queries few.
            var cache: [String: PlaceReference?] = [:]
            var located: [LocatedPhoto] = []
            for (index, sample) in samples.enumerated() {
                if Task.isCancelled {
                    return
                }
                if index.isMultiple(of: 200) {
                    state =
                        .reading(
                            "Placing \(index.formatted()) of \(samples.count.formatted()) photos…"
                        )
                }
                let latitude = (sample.coordinate.latitude * 100).rounded()
                let key = "\(latitude),\((sample.coordinate.longitude * 100).rounded())"
                let place: PlaceReference?
                if let cached = cache[key] {
                    place = cached
                } else {
                    place = await model.nearestCity(to: sample.coordinate, withinKm: 25)
                    cache[key] = place
                }
                if let place {
                    located.append(LocatedPhoto(sample: sample, place: place))
                }
            }
            suggestions = PhotoClustering.suggest(
                located,
                home: model.home,
                existing: model.log.visits
            )
            selected = Set(fresh.map(\.id))
            state = .done
        #else
            state = .denied
        #endif
    }

    #if canImport(Photos)
        /// Every image's date and location, and nothing else about it.
        nonisolated static func samples() -> [PhotoSample] {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let assets = PHAsset.fetchAssets(with: .image, options: options)
            var samples: [PhotoSample] = []
            samples.reserveCapacity(assets.count)
            assets.enumerateObjects { asset, _, _ in
                guard let date = asset.creationDate, let location = asset.location,
                      let coordinate = Coordinate(
                          validating: location.coordinate.latitude,
                          location.coordinate.longitude
                      ),
                      !(coordinate.latitude == 0 && coordinate.longitude == 0)
                else { return }
                samples.append(PhotoSample(taken: date, coordinate: coordinate))
            }
            return samples
        }
    #endif

    /// Suggestions read and chosen from: a long scan's result, not to lose by a swipe.
    private var hasReview: Bool {
        state == .done && !selected.isEmpty
    }

    /// What the system's settings are called where the user will find the switch.
    private static var settingsName: String {
        #if os(macOS)
            "System Settings"
        #else
            "Settings"
        #endif
    }

    /// Antipodes' own page in Settings on iPhone and iPad, where Photos access is; the
    /// Photos privacy pane on the Mac.
    private func openPrivacySettings() {
        #if os(macOS)
            let address = "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos"
        #else
            let address = UIApplication.openSettingsURLString
        #endif
        if let url = URL(string: address) {
            openURL(url)
        }
    }

    private func importSelected() {
        do {
            let count = try model.importSuggestions(
                suggestions.filter { selected.contains($0.id) },
                tripID: model.resolveTrip(tripID, newTripName: newTripName)
            )
            dismiss()
            model.announce("Added \(Format.ordinalCount(count, "visit"))")
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}
