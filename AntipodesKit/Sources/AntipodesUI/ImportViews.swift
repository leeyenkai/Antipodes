import AntipodesCore
import AntipodesImport
import AntipodesStore
import SwiftUI
import UniformTypeIdentifiers

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
                let cancelled = candidates.count { $0.status == .cancelled }
                if unmatched > 0 {
                    Label(
                        "\(unmatched) need an airport chosen",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(Palette.warning)
                }
                if duplicates > 0 {
                    Label(
                        "\(Format.ordinalCount(duplicates, "flight")) already logged, left out",
                        systemImage: "doc.on.doc"
                    )
                    .foregroundStyle(.secondary)
                }
                if cancelled > 0 {
                    Label(
                        "\(Format.ordinalCount(cancelled, "cancelled flight")), left out",
                        systemImage: "xmark.circle"
                    )
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
            failure = error.localizedDescription
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
            failure = error.localizedDescription
        }
    }

    private func apply(_ place: PlaceReference, to fix: Fix) {
        guard let index = candidates.firstIndex(where: { $0.row.line == fix.line }) else { return }
        switch fix.end {
        case .origin: candidates[index].origin = place
        case .destination: candidates[index].destination = place
        }
        candidates[index].include = candidates[index].leg != nil && !candidates[index].isDuplicate
            && !candidates[index].row.isCancelled
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
                .disabled(candidate.leg == nil || candidate.row.isCancelled)
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
                switch candidate.status {
                case .duplicate:
                    Label("Already logged", systemImage: "doc.on.doc")
                        .font(.caption2).foregroundStyle(.secondary)
                case .cancelled:
                    Label("Cancelled — never flown", systemImage: "xmark.circle")
                        .font(.caption2).foregroundStyle(.secondary)
                case .needsAirport:
                    Label(
                        "Tap the orange code to choose the airport",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption2).foregroundStyle(Palette.warning)
                case .ready:
                    EmptyView()
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

extension ImportCounts {
    /// "2 trips, 14 places, 3 journeys and 1 wishlist place", leaving out the kinds
    /// with none.
    var summary: String {
        [
            trips > 0 ? Format.ordinalCount(trips, "trip") : nil,
            visits > 0 ? Format.ordinalCount(visits, "place") : nil,
            journeys > 0 ? Format.ordinalCount(journeys, "journey") : nil,
            wishlist > 0 ? Format.ordinalCount(wishlist, "wishlist place") : nil,
        ]
        .compactMap(\.self)
        .formatted(.list(type: .and))
    }
}

extension BackupPreview {
    /// What restoring this file would do, said before anything is written (R-NAV-2).
    var confirmationMessage: String {
        guard additions.total > 0 else {
            return "Everything in this backup is already in your log."
        }
        var text = "This adds \(additions.summary) to your log."
        if alreadyInLog > 0 {
            text += " \(Format.ordinalCount(alreadyInLog, "record")) already in your log "
                + "stay as they are."
        }
        if additions.unfiled > 0 {
            text += """
             \(Format.ordinalCount(additions.unfiled, "record")) belonged to a trip that isn't \
            in the file, and will arrive unfiled.
            """
        }
        return text
    }
}
