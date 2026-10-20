import AntipodesCore
import AntipodesImport
import SwiftUI
import UniformTypeIdentifiers
#if canImport(Photos)
    import Photos
#endif

/// Imports another app's flight history with a review step for anything that did not
/// match (R-LOG-8, R-JLOG-7).
///
/// Either asks for a file, or — when one was dropped on the Mac window (R-NAV-2) — starts
/// from that file. Nothing is written until the user taps Import.
struct FlightImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let droppedFile: Data?

    @State private var isChoosingFile: Bool
    @State private var format: FlightLogFormat?
    @State private var candidates: [FlightImportCandidate] = []
    @State private var isReading = false
    @State private var tripID: UUID?
    @State private var fixing: Fix?
    @State private var failure: String?

    struct Fix: Identifiable {
        let line: Int
        let end: End

        enum End {
            case origin
            case destination
        }

        var id: String {
            "\(line)-\(end)"
        }
    }

    init(file: Data? = nil) {
        droppedFile = file
        _isChoosingFile = State(initialValue: file == nil)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isReading {
                    ProgressView("Matching airports…")
                } else if candidates.isEmpty {
                    EmptyStateView(
                        title: "Import flights",
                        message: failure ?? """
                        Choose a CSV exported from Flighty, myFlightradar24, OpenFlights or a \
                        spreadsheet with date, from and to columns.
                        """,
                        systemImage: "airplane.arrival",
                        actionTitle: "Choose File",
                        action: { isChoosingFile = true }
                    )
                } else {
                    review
                }
            }
            .navigationTitle("Import Flights")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                if !candidates.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import \(includedCount)", action: importSelected)
                            .disabled(includedCount == 0)
                    }
                }
            }
            .fileImporter(
                isPresented: $isChoosingFile,
                allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]
            ) { result in
                Task { await read(result) }
            }
            .sheet(item: $fixing) { fix in
                PlacePickerSheet(
                    title: "Choose airport",
                    prompt: "Airport name or code",
                    kinds: [.airport],
                    fixedKinds: [.airport]
                ) { place in
                    apply(place, to: fix)
                }
            }
            .task {
                if let droppedFile, candidates.isEmpty {
                    await match(droppedFile)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 480, idealHeight: 640)
        #endif
    }

    private var includedCount: Int {
        candidates.count { $0.include && $0.leg != nil }
    }

    private var review: some View {
        List {
            Section {
                if let format {
                    LabeledContent("Format", value: format.displayName)
                }
                LabeledContent("Flights found", value: "\(candidates.count)")
                let unmatched = candidates.count { $0.status == .needsAirport }
                let duplicates = candidates.count { $0.status == .duplicate }
                if unmatched > 0 {
                    Label(
                        "\(unmatched) need an airport chosen",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(Palette.warning)
                }
                if duplicates > 0 {
                    Label("\(duplicates) already in your log, left out", systemImage: "doc.on.doc")
                        .foregroundStyle(.secondary)
                }
                TripPicker(selection: $tripID)
            }
            Section("Flights") {
                ForEach($candidates) { $candidate in
                    CandidateRow(candidate: $candidate) { end in
                        fixing = Fix(line: candidate.row.line, end: end)
                    }
                }
            }
        }
    }

    private func read(_ result: Result<URL, any Error>) async {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            await match(data)
        } catch {
            failure = String(describing: error)
        }
    }

    private func match(_ data: Data) async {
        isReading = true
        defer { isReading = false }
        do {
            let (format, candidates) = try await model.readFlightLog(data)
            self.format = format
            self.candidates = candidates
            failure = nil
        } catch {
            failure = String(describing: error)
        }
    }

    private func apply(_ place: PlaceReference, to fix: Fix) {
        guard let index = candidates.firstIndex(where: { $0.row.line == fix.line }) else { return }
        switch fix.end {
        case .origin: candidates[index].origin = place
        case .destination: candidates[index].destination = place
        }
        candidates[index].include = candidates[index].leg != nil && !candidates[index].isDuplicate
    }

    private func importSelected() {
        do {
            let count = try model.importFlights(candidates, tripID: tripID)
            model.errorMessage = nil
            dismiss()
            _ = count
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

private struct CandidateRow: View {
    @Binding var candidate: FlightImportCandidate
    let fix: (FlightImportView.Fix.End) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("Include", isOn: $candidate.include)
                .labelsHidden()
                .disabled(candidate.leg == nil)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    endButton(
                        candidate.origin,
                        text: candidate.row.originCode ?? candidate.row.originText,
                        end: .origin
                    )
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    endButton(
                        candidate.destination,
                        text: candidate.row.destinationCode ?? candidate.row.destinationText,
                        end: .destination
                    )
                }
                Text([
                    candidate.row.date.displayText,
                    candidate.row.airline,
                    candidate.row.flightNumber,
                ]
                .compactMap(\.self).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if candidate.status == .duplicate {
                    Text("Already logged").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(candidate.row.problems, id: \.self) { problem in
                    Text(problem).font(.caption2).foregroundStyle(Palette.warning)
                }
            }
        }
    }

    private func endButton(
        _ place: PlaceReference?,
        text: String,
        end: FlightImportView.Fix.End
    ) -> some View {
        Button {
            fix(end)
        } label: {
            Text(place?.shortName ?? text)
                .font(.body.monospaced().weight(.semibold))
                .foregroundStyle(place == nil ? Palette.warning : .primary)
                .lineLimit(1)
        }
        .buttonStyle(.borderless)
    }
}

/// Suggests visits from where and when photos were taken (R-LOG-7, R-PRIV-4).
///
/// Opt-in: nothing is read until the user starts it, and the system's limited-library
/// choice is respected — only the photos the user allowed are read. Only each photo's
/// date and location are read, on the device, and nothing about a photo is stored: a
/// confirmed suggestion becomes an ordinary visit (decision D-17, Q-9).
struct PhotoImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var state: LoadState = .idle
    @State private var suggestions: [VisitSuggestion] = []
    @State private var selected: Set<String> = []
    @State private var tripID: UUID?

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
                        action: { Task { await scan() } }
                    )
                case let .reading(progress):
                    ProgressView(progress)
                case .denied:
                    EmptyStateView(
                        title: "No access to Photos",
                        message: """
                        Allow Antipodes to read your photos in Settings, or choose selected \
                        photos only.
                        """,
                        systemImage: "lock"
                    )
                case .done:
                    review
                }
            }
            .navigationTitle("Import from Photos")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
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
                    TripPicker(selection: $tripID)
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

    private func importSelected() {
        do {
            _ = try model.importSuggestions(
                suggestions.filter { selected.contains($0.id) },
                tripID: tripID
            )
            dismiss()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}
