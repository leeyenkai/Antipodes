import AntipodesImport
import AntipodesStore
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// On the Mac, accepts a flight-log CSV or an Antipodes backup dropped anywhere on the
    /// window (R-NAV-2, R-PLAT-3). Elsewhere it does nothing.
    func fileDropImport() -> some View {
        #if os(macOS)
            modifier(FileDropImport())
        #else
            self
        #endif
    }
}

#if os(macOS)
    /// Drag-and-drop import for the Mac window.
    ///
    /// Nothing is written until the user has seen what the file holds and said yes: a
    /// flight log opens the same review as Settings ▸ Import ▸ Flights, and a backup says
    /// what restoring it would add before it adds anything.
    private struct FileDropImport: ViewModifier {
        @Environment(AppModel.self) private var model
        @State private var isTargeted = false
        @State private var flightLog: DroppedFlightLog?
        @State private var backup: DroppedBackup?
        @State private var outcome: String?
        /// The result of a restore, held until the confirmation alert has gone: an
        /// alert asked for from another alert's button would never appear.
        @State private var pendingOutcome: String?

        func body(content: Content) -> some View {
            content
                .dropDestination(for: URL.self) { urls, _ in
                    isTargeted = false
                    Task { await receive(urls) }
                }
                .onDropSessionUpdated { session in
                    isTargeted = session.phase == .entering || session.phase == .active
                }
                .overlay {
                    if isTargeted {
                        DropTargetOverlay()
                    }
                }
                .sheet(item: $flightLog) { file in
                    FlightImportView(file: file.data)
                }
                .alert(
                    backup.map(\.title) ?? "",
                    isPresented: Binding(
                        get: { backup != nil },
                        set: {
                            if !$0 {
                                backup = nil
                            }
                        }
                    ),
                    presenting: backup
                ) { backup in
                    if backup.preview.additions.total > 0 {
                        Button("Import") { restore(backup) }
                        Button("Cancel", role: .cancel) {}
                    } else {
                        Button("OK", role: .cancel) {}
                    }
                } message: { backup in
                    Text(backup.message)
                }
                .alert(
                    "Backup imported",
                    isPresented: Binding(
                        get: { outcome != nil },
                        set: {
                            if !$0 {
                                outcome = nil
                            }
                        }
                    )
                ) {
                    Button("OK") { outcome = nil }
                } message: {
                    Text(outcome ?? "")
                }
                .onChange(of: backup == nil) { _, isGone in
                    guard isGone, let pending = pendingOutcome else { return }
                    pendingOutcome = nil
                    Task {
                        // Let the confirmation finish leaving before the next appears.
                        try? await Task.sleep(for: .milliseconds(300))
                        outcome = pending
                    }
                }
        }

        /// Takes the first file dropped. Each import has its own review, so a second
        /// file waits for a second drop rather than queueing behind the first.
        private func receive(_ urls: [URL]) async {
            guard let url = urls.first(where: \.isFileURL) else {
                model.errorMessage = """
                Drop a file saved on this Mac — a journey list as CSV or JSON, or an Antipodes \
                backup. Links and text can't be imported.
                """
                return
            }
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                // Off the main thread: a file on a network volume can take its time.
                let data = try await Task.detached(priority: .userInitiated) {
                    try Data(contentsOf: url)
                }.value
                switch DroppedFileKind(url) {
                case .backup:
                    do {
                        backup = try DroppedBackup(
                            fileName: url.lastPathComponent,
                            preview: model.previewBackup(data)
                        )
                    } catch {
                        // JSON that is not a backup may be another app's journey list.
                        guard (try? FlightLogImport.parse(data, dayFirst: true)) != nil else {
                            throw error
                        }
                        flightLog = DroppedFlightLog(data: data)
                    }
                case .flightLog:
                    flightLog = DroppedFlightLog(data: data)
                case nil:
                    model.errorMessage = """
                    Antipodes can import a journey list saved as CSV or JSON, or an Antipodes \
                    backup. “\(url.lastPathComponent)” is neither.
                    """
                }
            } catch {
                model.errorMessage = """
                “\(url.lastPathComponent)” couldn't be read: \(error.localizedDescription)
                """
            }
        }

        private func restore(_ backup: DroppedBackup) {
            do {
                let counts = try model.importBackup(backup.preview)
                pendingOutcome = "Added \(counts.summary)."
            } catch {
                model.errorMessage = """
                That backup couldn't be imported: \(error.localizedDescription)
                """
            }
        }
    }

    /// Which import a dropped file goes to, by its type.
    private enum DroppedFileKind {
        case backup
        case flightLog

        /// JSON is a backup, because that is the only JSON Antipodes reads; any other
        /// text is treated as a flight log, and the flight review says if it is not one.
        init?(_ url: URL) {
            guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
            if type.conforms(to: .json) {
                self = .backup
            } else if type.conforms(to: .text) {
                self = .flightLog
            } else {
                return nil
            }
        }
    }

    private struct DroppedFlightLog: Identifiable {
        let id = UUID()
        let data: Data
    }

    /// A backup that has been read and compared with the log, waiting for a yes.
    private struct DroppedBackup {
        let fileName: String
        let preview: BackupPreview

        var title: String {
            preview.additions.total > 0
                ? "Import “\(fileName)”?"
                : "Nothing new in “\(fileName)”"
        }

        var message: String {
            preview.confirmationMessage
        }
    }

    /// The window's highlight while a file is held over it.
    private struct DropTargetOverlay: View {
        var body: some View {
            ZStack {
                Rectangle()
                    .fill(.background.opacity(0.55))
                VStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Palette.visited)
                    Text("Drop to Import")
                        .font(.title2.weight(.semibold))
                    Text("A flight log saved as CSV, or an Antipodes backup (JSON)")
                        .foregroundStyle(.secondary)
                }
                .padding(32)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        Palette.visited,
                        style: StrokeStyle(lineWidth: 3, dash: [10, 6])
                    )
                    .padding(8)
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }
#endif
