import AntipodesCore
import AntipodesExport
import AntipodesPlaces
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
                sourcesSection
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

            Picker(
                "Countries counted",
                selection: Binding(
                    get: { model.rules.countryList },
                    set: { model.selectCountryList($0) }
                )
            ) {
                ForEach(CountryList.allCases) { list in
                    Text("\(list.displayName) (\(countryCount(for: list)))").tag(list)
                }
            }
        } header: {
            Text("Units and denominators")
        } footer: {
            Text("""
            "Share of the world" divides by the list you pick. \
            \(model.rules.countryList.explanation)
            """)
        }
    }

    private func countryCount(for list: CountryList) -> Int {
        model.countryListCounts[list] ?? list.fallbackCount
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

    /// Credits every source the place database was built from (R-DB-7).
    ///
    /// Attribution is a licence condition for GeoNames (CC BY 4.0), not a courtesy, so
    /// the required credit lines are shown first and verbatim, exactly as the pipeline
    /// wrote them into the database. The rest of the list is there because someone
    /// looking at a number deserves to know where it came from.
    @ViewBuilder
    private var sourcesSection: some View {
        if let info = model.databaseInfo, !info.sources.isEmpty {
            Section {
                ForEach(info.requiredAttributions, id: \.self) { credit in
                    Text(credit).font(.footnote)
                }
                ForEach(info.sources) { source in
                    NavigationLink {
                        SourceDetailView(source: source)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                            Text("\(source.licence) · \(source.usedFor)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Where the places come from")
            } footer: {
                Text("""
                Built from open data. No OpenStreetMap data is included: its licence \
                puts share-alike terms on a database built from it, which would apply \
                to this one.
                """)
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

/// One source's licence, obligation and the snapshot this database was built from.
struct SourceDetailView: View {
    let source: PlaceDataSource

    var body: some View {
        Form {
            Section("Licence") {
                LabeledContent("Licence", value: source.licence)
                if let licenceURL = source.licenceURL, let url = URL(string: licenceURL) {
                    Link("Read the licence", destination: url)
                }
                if let url = URL(string: source.url) {
                    Link(source.name, destination: url)
                }
            }

            if let attribution = source.attribution {
                Section {
                    Text(attribution)
                } header: {
                    Text("Required credit")
                } footer: {
                    Text("This licence requires the credit above wherever the data is used.")
                }
            }

            Section("Used for") {
                Text(source.usedFor)
            }

            // Which snapshot this build read. GeoNames and OurAirports publish daily,
            // so for those this is the only record of which day's data is in the app.
            if source.sha256 != nil || source.retrieved != nil {
                Section("This build") {
                    if let retrieved = source.retrieved {
                        LabeledContent("Retrieved", value: retrieved)
                    }
                    if let digest = source.sha256 {
                        LabeledContent("Digest", value: String(digest.prefix(16)))
                            .font(.caption.monospaced())
                    }
                }
            }
        }
        .navigationTitle(source.name)
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
