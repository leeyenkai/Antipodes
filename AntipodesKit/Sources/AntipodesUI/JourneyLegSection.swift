import AntipodesCore
import SwiftUI

/// One leg: collapsed to a summary, or expanded into its fields.
struct LegSection: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: LegDraft
    let number: Int
    let isOnly: Bool
    let isExpanded: Bool
    let expand: () -> Void
    let remove: () -> Void
    let pick: (LegEnd) -> Void
    let pickTransit: () -> Void

    @State private var showsDetails = false

    var body: some View {
        Section {
            if isExpanded || isOnly {
                fields
            } else {
                Button(action: expand) {
                    LegSummary(draft: draft)
                }
                .buttonStyle(.plain)
            }
        } header: {
            HStack {
                Text(isOnly ? "Leg" : "Leg \(number)")
                Spacer()
                if !isOnly {
                    Menu {
                        Button(
                            isExpanded ? "Collapse" : "Edit",
                            systemImage: "pencil",
                            action: expand
                        )
                        Button(
                            "Remove Leg",
                            systemImage: "trash",
                            role: .destructive,
                            action: remove
                        )
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Leg \(number) options")
                }
            }
        }
    }

    @ViewBuilder
    private var fields: some View {
        if let route = draft.routeName {
            Label {
                VStack(alignment: .leading) {
                    Text(route).font(.headline)
                    Text("Catalogue route. Change either end to log the section you rode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .foregroundStyle(Palette.mode(draft.mode))
            }
        }

        Picker("Mode", selection: $draft.mode) {
            ForEach(TravelMode.loggable) { mode in
                Label(mode.displayName, systemImage: mode.symbolName).tag(mode)
            }
        }
        .onChange(of: draft.mode) {
            let original = draft
            let networks = model.trackNetworks
            Task {
                let measured = await LegDraft.measured(original, along: networks)
                draft.adoptMeasurement(measured, madeFrom: original)
            }
        }

        if draft.mode == .cityTransit {
            TransitLineButton(lineID: draft.transitLineID, action: pickTransit)
        }

        EndpointButton(label: "From", place: draft.origin, mode: draft.mode) { pick(.origin) }
        EndpointButton(label: "To", place: draft.destination, mode: draft.mode) {
            pick(.destination)
        }

        FlexibleDateField(date: $draft.date)

        if let leg = draft.leg {
            LegDistanceRow(leg: leg)
        }

        DisclosureGroup(isExpanded: $showsDetails) {
            LegDetailFields(draft: $draft)
        } label: {
            Label(
                draft.hasDetails ? "Details" : "Add times, seat and more",
                systemImage: "list.bullet.rectangle"
            )
        }
        .onAppear { showsDetails = draft.hasDetails }
    }
}
