import AntipodesCore
import AntipodesExport
import AntipodesPlaces
import AntipodesStore
import SwiftUI
import UniformTypeIdentifiers

/// Appearance, home, counting rules, units, import and export, the database, credits,
/// privacy and the delete button (§9).
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// In the iPad and Mac sidebar, Settings is a destination of its own rather than a
    /// sheet, so there is nothing for a Done button to close.
    var isDestination = false

    @State private var isConfirmingDelete = false
    @State private var isPickingHome = false
    @State private var exportedJSON: ExportDocument?
    @State private var exportedCSV: CSVFolderDocument?
    @State private var isImportingBackup = false
    @State private var isImportingFlights = false
    @State private var isImportingPhotos = false
    @State private var message: String?
    /// A backup read and compared with the log, waiting for the user's yes.
    @State private var pendingBackup: BackupPreview?

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                countingSection
                unitsSection
                importSection
                exportSection
                syncSection
                databaseSection
                sourcesSection
                privacySection
                aboutSection
                deleteSection
            }
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if !isDestination {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .alert("Delete everything?", isPresented: $isConfirmingDelete) {
                Button("Delete Everything", role: .destructive, action: deleteEverything)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("""
                Every trip, place, journey and wishlist entry is removed from this device. If \
                you're signed in to iCloud, the copy there is removed as this device syncs — \
                keep the app open and online for a moment afterwards. This can't be undone.
                """)
            }
            .alert(
                "Done",
                isPresented: Binding(get: { message != nil }, set: {
                    if !$0 {
                        message = nil
                    }
                })
            ) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
            .fileExporter(
                isPresented: Binding(
                    get: { exportedJSON != nil },
                    set: {
                        if !$0 {
                            exportedJSON = nil
                        }
                    }
                ),
                document: exportedJSON,
                contentType: .json,
                defaultFilename: "Antipodes \(CalendarDate.today().iso)"
            ) { result in
                if case let .failure(error) = result {
                    model.errorMessage = error.localizedDescription
                }
            }
            .fileExporter(
                isPresented: Binding(
                    get: { exportedCSV != nil },
                    set: {
                        if !$0 {
                            exportedCSV = nil
                        }
                    }
                ),
                document: exportedCSV,
                contentType: .folder,
                defaultFilename: "Antipodes CSV \(CalendarDate.today().iso)"
            ) { result in
                if case let .failure(error) = result {
                    model.errorMessage = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $isImportingBackup, allowedContentTypes: [.json]) { result in
                importBackup(result)
            }
            .alert(
                pendingBackup
                    .map { $0.additions.total > 0 ? "Restore this backup?" : "Nothing new" } ?? "",
                isPresented: Binding(
                    get: { pendingBackup != nil },
                    set: {
                        if !$0 {
                            pendingBackup = nil
                        }
                    }
                ),
                presenting: pendingBackup
            ) { preview in
                if preview.additions.total > 0 {
                    Button("Restore") { restore(preview) }
                    Button("Cancel", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: { preview in
                Text(preview.confirmationMessage)
            }
            .sheet(isPresented: $isImportingFlights) {
                FlightImportView()
            }
            .sheet(isPresented: $isImportingPhotos) {
                PhotoImportView()
            }
            .sheet(isPresented: $isPickingHome) {
                PlacePickerSheet(
                    title: "Home",
                    prompt: "Search your home city",
                    kinds: [.city],
                    fixedKinds: [.city]
                ) {
                    model.home = $0
                }
            }
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        @Bindable var model = model
        return Section {
            Picker("Appearance", selection: $model.appearance) {
                ForEach(AppearancePreference.allCases) { Text($0.displayName).tag($0) }
            }
            Button {
                isPickingHome = true
            } label: {
                LabeledContent("Home") {
                    Text(model.home.map { "\($0.flag) \($0.name)" } ?? "Not set")
                        .foregroundStyle(model.home == nil ? .secondary : .primary)
                }
            }
            .buttonStyle(.plain)
            if model.home != nil {
                Button("Clear Home", role: .destructive) { model.home = nil }
            }
        } footer: {
            Text(
                """
                Home is left out of days away and photo suggestions, and is where your antipode \
                is measured from.
                """
            )
        }
    }

    private var countingSection: some View {
        @Bindable var model = model
        return Section {
            Toggle("Count places you passed through", isOn: $model.rules.includePassedThrough)
            Toggle("Count layovers", isOn: $model.rules.includeLayovers)
            Toggle("Include commutes in stats", isOn: $model.rules.includeCommutes)
        } header: {
            Text("What counts")
        } footer: {
            Text("""
            Every statistic, badge and the globe's shading follow these rules. Changing one \
            recomputes everything immediately.
            """)
        }
    }

    private var unitsSection: some View {
        @Bindable var model = model
        return Section {
            Picker("Units", selection: $model.rules.unitSystem) {
                ForEach(UnitSystem.allCases) { Text($0.displayName).tag($0) }
            }
            Picker(
                "Countries counted",
                selection: Binding(
                    get: { model.rules.countryList },
                    set: { model.selectCountryList($0) }
                )
            ) {
                ForEach(CountryList.allCases) { list in
                    Text("\(list.displayName) (\(model.countryCount(for: list)))").tag(list)
                }
            }
        } header: {
            Text("Units and countries")
        } footer: {
            Text(
                """
                \"Share of the world\" divides by the list you pick. \
                \(model.rules.countryList.explanation)
                """
            )
        }
    }

    private var importSection: some View {
        Section {
            Button("Flight History (CSV)…", systemImage: "airplane.arrival") {
                isImportingFlights = true
            }
            Button("From Photos…", systemImage: "photo.on.rectangle.angled") {
                isImportingPhotos = true
            }
            Button("Antipodes Backup (JSON)…", systemImage: "arrow.down.doc") {
                isImportingBackup = true
            }
        } header: {
            Text("Import")
        } footer: {
            Text("""
            Flight lists from Flighty, myFlightradar24, OpenFlights or any CSV with date, from \
            and to columns. Photos are read on this device for their date and place; nothing \
            is uploaded or copied.\(dropHint)
            """)
        }
    }

    /// On the Mac, either file can also be dropped on the window (R-NAV-2).
    private var dropHint: String {
        #if os(macOS)
            " You can also drop a flight list or a backup anywhere on the window."
        #else
            ""
        #endif
    }

    private var exportSection: some View {
        Section {
            Button("Export as JSON", systemImage: "curlybraces") { exportJSON() }
            Button("Export as CSV", systemImage: "tablecells") {
                exportedCSV = CSVFolderDocument(files: model.exportCSVFiles())
            }
        } header: {
            Text("Export")
        } footer: {
            Text("""
            Every trip, place, journey and wishlist entry, in files you can read without \
            this app. The JSON export can be imported again as a backup.
            """)
        }
    }

    private var syncSection: some View {
        Section("iCloud") {
            if FileManager.default.ubiquityIdentityToken != nil {
                Label("Syncing through your private iCloud", systemImage: "icloud")
            } else {
                Label("Stored on this device only", systemImage: "iphone")
                Text(
                    """
                    Sign in to iCloud to keep your log in step across your devices. The developer \
                    never sees it.
                    """
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var databaseSection: some View {
        Section("Place database") {
            if let info = model.databaseInfo {
                LabeledContent("Version", value: info.dataVersion)
                LabeledContent("Places", value: info.totalRows.formatted())
                ForEach(
                    info.rowCounts.keys.sorted { $0.rawValue < $1.rawValue },
                    id: \.self
                ) { kind in
                    LabeledContent(kind.pluralName, value: (info.rowCounts[kind] ?? 0).formatted())
                }
                LabeledContent("Collections", value: "\(model.catalogue.collections.count)")
                LabeledContent("Badges", value: "\(model.catalogue.achievements.count)")
            } else if let error = model.placesError {
                Text(error).font(.caption).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
    }

    /// Credits every source the place database was built from (R-DB-7).
    ///
    /// Attribution is a licence condition for GeoNames (CC BY 4.0) and the UK
    /// Government's conversion factors (OGL v3), not a courtesy, so the required credit
    /// lines are shown first and verbatim, exactly as the pipeline wrote them into the
    /// database.
    @ViewBuilder
    private var sourcesSection: some View {
        if let info = model.databaseInfo, !info.sources.isEmpty {
            Section {
                ForEach(info.requiredAttributions, id: \.self) { credit in
                    Text(credit).font(.footnote)
                }
                Text("Country outlines from Natural Earth (public domain).")
                    .font(.footnote)
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
                Text("Where the data comes from")
            } footer: {
                Text("""
                Built from open data. No OpenStreetMap data is included: its licence puts \
                share-alike terms on a database built from it, which would apply to this one.
                """)
            }
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Label("No account, no server, no analytics", systemImage: "lock.shield")
            Label("Searches and maps never leave this device", systemImage: "magnifyingglass")
            Label("Your log syncs only through your own iCloud", systemImage: "icloud")
        }
        .font(.callout)
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.versionString)
            NavigationLink("How Antipodes counts") {
                CountingExplainer()
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Delete Everything", role: .destructive) { isConfirmingDelete = true }
        } footer: {
            Text(
                """
                Removes your whole log from this device and your iCloud. Export first \
                if you want a copy.
                """
            )
        }
    }

    // MARK: - Actions

    private func exportJSON() {
        do {
            exportedJSON = try ExportDocument(data: model.exportJSON())
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func importBackup(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            pendingBackup = try model.previewBackup(Data(contentsOf: url))
        } catch {
            model.errorMessage = "That file couldn't be imported. \(error.localizedDescription)"
        }
    }

    private func restore(_ preview: BackupPreview) {
        do {
            let counts = try model.importBackup(preview)
            pendingBackup = nil
            Task {
                // Let the confirmation leave before the result appears.
                try? await Task.sleep(for: .milliseconds(300))
                message = "Added \(counts.summary)."
            }
        } catch {
            model.errorMessage = "That backup couldn't be restored. \(error.localizedDescription)"
        }
    }

    private func deleteEverything() {
        do {
            try model.deleteEverything()
            message = "Everything on this device has been deleted."
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}
