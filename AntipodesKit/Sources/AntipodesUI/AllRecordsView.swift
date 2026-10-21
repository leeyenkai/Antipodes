import AntipodesCore
import SwiftUI

/// Every visit in one sortable table, for bulk work: select many, then change their
/// type, date or trip at once, or delete them (R-PLAT-3, R-NAV-2).
///
/// A table on iPad and Mac, where there is room for columns; a list on iPhone.
struct AllRecordsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: Set<UUID> = []
    @State private var sortOrder = [KeyPathComparator(\Row.sortDate, order: .reverse)]
    @State private var searchText = ""
    @State private var isSettingDate = false
    @State private var bulkDate: FlexibleDate = .day(.today())
    @State private var isConfirmingDelete = false
    @State private var openedVisit: UUID?

    struct Row: Identifiable {
        let id: UUID
        let name: String
        let country: String
        let type: String
        let date: String
        let sortDate: String
        let trip: String
        let visit: Visit
    }

    var body: some View {
        Group {
            if sizeClass == .compact {
                List(rows, selection: $selection) { row in
                    NavigationLink(value: LogRoute.visit(row.id)) {
                        VisitRow(visit: row.visit)
                    }
                }
            } else {
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Place", value: \.name)
                    TableColumn("Country", value: \.country)
                    TableColumn("Type", value: \.type)
                    TableColumn("Date", value: \.sortDate) { row in
                        Text(row.date)
                    }
                    TableColumn("Trip", value: \.trip)
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    bulkActions(ids)
                } primaryAction: { ids in
                    openedVisit = ids.first
                }
            }
        }
        .overlay {
            if rows.isEmpty {
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView(
                        "No places logged",
                        systemImage: "tablecells",
                        description: Text(
                            "Every place you log appears here, ready to edit in bulk."
                        )
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Filter by place or country")
        .deleteSelectionCommand(isEnabled: !selection.isEmpty) { isConfirmingDelete = true }
        .navigationDestination(item: $openedVisit) { VisitDetailView(visitID: $0) }
        .navigationTitle("All Records")
        .toolbar {
            #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    bulkActions(selection)
                } label: {
                    Label("Edit \(selection.count) Selected", systemImage: "ellipsis.circle")
                }
                .disabled(selection.isEmpty)
            }
        }
        .sheet(isPresented: $isSettingDate) {
            NavigationStack {
                Form {
                    Section {
                        FlexibleDateField(date: $bulkDate)
                    } footer: {
                        Text("Sets this date on \(Format.ordinalCount(selection.count, "visit")).")
                    }
                }
                .navigationTitle("Set Date")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { isSettingDate = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            update(selection) { $0.date = bulkDate }
                            isSettingDate = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Delete \(Format.ordinalCount(selection.count, "visit"))?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                model.deleteVisits(Array(selection))
                selection = []
            }
        }
    }

    @ViewBuilder
    private func bulkActions(_ ids: Set<UUID>) -> some View {
        Menu("Visit Type", systemImage: "figure.walk") {
            ForEach(VisitType.allCases) { type in
                Button(type.displayName) { update(ids) { $0.visitType = type } }
            }
        }
        Button("Set Date…", systemImage: "calendar") {
            selection = ids
            isSettingDate = true
        }
        MoveToTripMenu(visitIDs: Array(ids))
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) {
            selection = ids
            isConfirmingDelete = true
        }
    }

    private func update(_ ids: Set<UUID>, _ change: (inout Visit) -> Void) {
        let changed = model.log.visits.filter { ids.contains($0.id) }.map { visit in
            var copy = visit
            change(&copy)
            return copy
        }
        model.updateVisits(changed)
    }

    private var rows: [Row] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let trips = Dictionary(
            model.log.trips.map { ($0.id, $0.displayName(model: model)) },
            uniquingKeysWith: { first, _ in first }
        )
        return model.log.visits
            .filter { visit in
                query.isEmpty || visit.place.name.lowercased().contains(query)
                    || (visit.place.countryName?.lowercased().contains(query) ?? false)
            }
            .map { visit in
                Row(
                    id: visit.id,
                    name: visit.place.name,
                    country: [visit.place.flag, visit.place.countryName ?? ""]
                        .joined(separator: " "),
                    type: visit.visitType.displayName,
                    date: visit.date.displayText,
                    sortDate: visit.date.sortDay?.iso ?? "",
                    trip: visit.tripID.flatMap { trips[$0] } ?? "",
                    visit: visit
                )
            }
            .sorted(using: sortOrder)
    }
}

extension View {
    /// ⌫ on the Mac deletes the selected rows, after asking, as the menu does. iOS has
    /// no delete command; the menu and swipe actions cover it there.
    @ViewBuilder
    func deleteSelectionCommand(isEnabled: Bool, perform: @escaping () -> Void) -> some View {
        #if os(macOS)
            onDeleteCommand(perform: isEnabled ? perform : nil)
        #else
            self
        #endif
    }
}
