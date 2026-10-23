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
    @State private var isImportingTracks = false
    /// A backup read and compared with the log, waiting for the user's yes.
    @State private var pendingBackup: BackupPreview?

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                dataSection
                importSection
                countingSection
                unitsSection
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
                Every trip, place, journey and wishlist entry is removed. Your log is kept \
                only on this device, so this can't be undone — export a backup first if \
                you want a copy.
                """)
            }
            // A sheet covers the app's own toast, so it shows its own: what a restore or
            // an import added, or that the log was deleted.
            .overlay(alignment: .bottom) {
                if !isDestination {
                    UndoToast()
                        .padding(.bottom, 16)
                }
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
            .sheet(isPresented: $isImportingTracks) {
                TrackImportView()
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
            // Only where the satellite picture is in the bundle, as on the globe's own
            // menu; without it the choice would quietly fall back to the standard globe.
            if GlobeImageryStore().isAvailable {
                Picker("Globe", selection: $model.globeStyle) {
                    ForEach(GlobeStyle.allCases) { Text($0.displayName).tag($0) }
                }
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
                Button("Clear Home") { model.home = nil }
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

    /// Where the log is kept, and the ways to keep a copy of it or bring it back
    /// (R-PRIV-6, R-LOG-9, D-31): there is no other copy anywhere, so these are near
    /// the top.
    private var dataSection: some View {
        Section {
            Label("Kept on this device only", systemImage: "lock")
            Button("Export Backup…", systemImage: "arrow.up.doc") { exportJSON() }
            Button("Restore from Backup…", systemImage: "arrow.down.doc") {
                isImportingBackup = true
            }
            Button("Export as CSV…", systemImage: "tablecells") {
                exportedCSV = CSVFolderDocument(files: model.exportCSVFiles())
            }
        } header: {
            Text("Your data")
        } footer: {
            Text("""
            No account, no sync and no copy anywhere else. A backup is one JSON file with \
            every trip, place, journey and wishlist entry: keep it somewhere safe, or \
            restore it on another device. The CSV files open in any spreadsheet.\(dropHint)
            """)
        }
    }

    private var importSection: some View {
        Section {
            Button("Flights, Trains and Other Journeys…", systemImage: "airplane.arrival") {
                isImportingFlights = true
            }
            Button("Find Visits in Photos…", systemImage: "photo.on.rectangle.angled") {
                isImportingPhotos = true
            }
            Button("Hikes and Rides (GPX or Health)…", systemImage: "figure.hiking") {
                isImportingTracks = true
            }
        } header: {
            Text("Import")
        } footer: {
            Text("""
            Flight lists from Flighty, myFlightradar24 or OpenFlights, and rail logs or any \
            CSV or JSON list of journeys with date, from and to. Hikes and rides from GPX \
            files or Apple Health keep the way you went. Photos and workouts are read on \
            this device; nothing is uploaded or copied.
            """)
        }
    }

    /// On the Mac, a journey list or a backup can also be dropped on the window (R-NAV-2).
    private var dropHint: String {
        #if os(macOS)
            " You can also drop a backup or a journey list anywhere on the window."
        #else
            ""
        #endif
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
                Text("""
                Satellite globe: Blue Marble Next Generation, NASA Earth Observatory \
                (Reto Stöckli), public domain.
                """)
                .font(.footnote)
                Text("""
                Climate: TerraClimate, Abatzoglou et al. (2018), Scientific Data 5:170191, \
                University of Idaho, CC0.
                """)
                .font(.footnote)
                if let pack = model.routePack {
                    Text("""
                    Trails, lifts, route shapes and city transit lines: \(pack.attribution). \
                    Map of \(pack.snapshot).
                    """)
                    .font(.footnote)
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
                Text("Where the data comes from")
            } footer: {
                Text("""
                Built from open data. OpenStreetMap's is kept in a file of its own, \
                routes-osm.sqlite, under the Open Database License: its share-alike terms \
                reach that file and nothing else.
                """)
            }
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Label("No account, no server, no analytics", systemImage: "lock.shield")
            Label("Searches and maps never leave this device", systemImage: "magnifyingglass")
            Label("Your log is stored on this device and nowhere else", systemImage: "lock")
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
            Text("Removes your whole log. Export a backup first if you want a copy.")
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
            model.announce("Restored \(counts.summary)")
        } catch {
            model.errorMessage = "That backup couldn't be restored. \(error.localizedDescription)"
        }
    }

    private func deleteEverything() {
        do {
            try model.deleteEverything()
            model.announce("Your log has been deleted", systemImage: "trash")
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}
