import AntipodesCore
import AntipodesExport
import SwiftUI
import UniformTypeIdentifiers

/// Counting rules, units, the database version, export and delete (§9).
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    @State private var isConfirmingDelete = false
    @State private var exportDocument: ExportDocument?
    @State private var isExporting = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                countingSection
                unitsSection
                databaseSection
                dataSection
                privacySection
            }
            .navigationTitle("Settings")
            .task { await model.loadDatabaseInfo() }
            .alert("Delete everything?", isPresented: $isConfirmingDelete) {
                Button("Delete", role: .destructive, action: deleteEverything)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("""
                This removes every trip, place and journey from this device. If you are \
                signed in to iCloud, the copy there is removed as this device syncs.
                """)
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "antipodes-export"
            ) { result in
                if case let .failure(error) = result {
                    message = String(describing: error)
                }
            }
        }
    }

    private var countingSection: some View {
        Section {
            Toggle(
                "Count places you passed through",
                isOn: Binding(
                    get: { model.rules.includePassedThrough },
                    set: { model.rules.includePassedThrough = $0 }
                )
            )
            Toggle(
                "Count layovers",
                isOn: Binding(
                    get: { model.rules.includeLayovers },
                    set: { model.rules.includeLayovers = $0 }
                )
            )
            Toggle(
                "Include commutes in stats",
                isOn: Binding(
                    get: { model.rules.includeCommutes },
                    set: { model.rules.includeCommutes = $0 }
                )
            )
        } header: {
            Text("What counts")
        } footer: {
            Text("""
            Every statistic in the app follows these rules. Changing one recomputes \
            your numbers immediately.
            """)
        }
    }

    private var unitsSection: some View {
        Section {
            Picker(
                "Units",
                selection: Binding(
                    get: { model.rules.unitSystem },
                    set: { model.rules.unitSystem = $0 }
                )
            ) {
                ForEach(UnitSystem.allCases) { system in
                    Text(system.displayName).tag(system)
                }
            }

            Stepper(
                value: Binding(
                    get: { model.rules.worldCountryCount },
                    set: { model.rules.worldCountryCount = $0 }
                ),
                in: 100 ... 300
            ) {
                VStack(alignment: .leading) {
                    Text("Countries in the world")
                    Text("\(model.rules.worldCountryCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Units and denominators")
        } footer: {
            Text("""
            "Share of the world" divides by this number. 193 is the UN member states; \
            counting territories gives a larger figure. Which list to offer is still \
            an open question.
            """)
        }
    }

    private var databaseSection: some View {
        Section("Place database") {
            if let info = model.databaseInfo {
                LabeledContent("Version", value: info.dataVersion)
                LabeledContent("Built", value: info.builtAt)
                LabeledContent("Places", value: "\(info.totalRows)")
                ForEach(
                    info.rowCounts.keys.sorted { $0.rawValue < $1.rawValue },
                    id: \.self
                ) { kind in
                    LabeledContent(kind.displayName, value: "\(info.rowCounts[kind] ?? 0)")
                }
            } else if let error = model.placesError {
                Text(error).font(.caption).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
    }

    private var dataSection: some View {
        Section {
            Button("Export as JSON") { exportJSON() }
            Button("Delete everything", role: .destructive) { isConfirmingDelete = true }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Your data")
        } footer: {
            Text("""
            Export gives you every trip, place and journey in a file you can read \
            without this app.
            """)
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Label("No account, no server, no analytics", systemImage: "lock.shield")
            Label("Searches never leave this device", systemImage: "magnifyingglass")
            Label("Syncs through your own iCloud", systemImage: "icloud")
        }
        .font(.callout)
    }

    private func exportJSON() {
        do {
            exportDocument = try ExportDocument(data: model.exportJSON())
            isExporting = true
        } catch {
            message = String(describing: error)
        }
    }

    private func deleteEverything() {
        do {
            try model.deleteEverything()
            message = "Everything on this device has been deleted."
        } catch {
            message = String(describing: error)
        }
    }
}

/// Wraps export bytes for `fileExporter`.
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
