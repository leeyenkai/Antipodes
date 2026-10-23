import AntipodesCore
import AntipodesImport
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var isAttachingTrack = false

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
            if draft.mode == .humanPowered, draft.activity == nil {
                draft.activity = .hike
            }
            remeasure()
        }

        if draft.mode == .humanPowered {
            Picker("Activity", selection: $draft.activity) {
                ForEach(HumanActivity.allCases) { activity in
                    Label(activity.displayName, systemImage: activity.symbolName)
                        .tag(HumanActivity?.some(activity))
                }
            }
            .onChange(of: draft.activity) { remeasure() }
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

        if let track = draft.recordedTrack {
            RecordedTrackRow(track: track) {
                draft.recordedTrack = nil
                remeasure()
            }
        } else if draft.mode == .humanPowered {
            Button(
                "Attach a Recorded Track (GPX)…",
                systemImage: "point.bottomleft.forward.to.point.topright.scurvepath"
            ) {
                isAttachingTrack = true
            }
            .fileImporter(isPresented: $isAttachingTrack, allowedContentTypes: [.gpx]) { result in
                attachTrack(result)
            }
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

    /// Measures the leg again along whichever network its mode and activity now take.
    private func remeasure() {
        let original = draft
        Task {
            let measured = await LegDraft.measured(original, model: model)
            draft.adoptMeasurement(measured, madeFrom: original)
        }
    }

    /// Reads a GPX file into the leg: its track, and its ends and date where the leg
    /// has none yet (R-PATH-1).
    private func attachTrack(_ result: Result<URL, any Error>) {
        guard case let .success(url) = result else { return }
        Task {
            guard let data = readSecurityScoped(url) else {
                model.errorMessage = "That file couldn't be opened."
                return
            }
            do {
                guard let first = try GPXReader.read(data).first,
                      let track = first.recordedTrack else { return }
                draft.recordedTrack = track
                draft.activity = first.activity
                if draft.origin == nil, let start = track.points.first {
                    draft.origin = await model.nearestCity(to: start, withinKm: 25)
                }
                if draft.destination == nil, let end = track.points.last {
                    draft.destination = await model.nearestCity(to: end, withinKm: 25)
                }
                if let start = first.start.flatMap({ CalendarDate($0) }) {
                    draft.date = .day(start)
                }
            } catch {
                model.errorMessage = "That file has no track to attach."
            }
        }
    }
}

/// A recorded track's figures: how far, how high, how long, and a way to drop it.
struct RecordedTrackRow: View {
    @Environment(AppModel.self) private var model
    let track: RecordedTrack
    let remove: () -> Void

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recorded track")
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath")
            }
            Spacer()
            Button("Remove", systemImage: "xmark.circle.fill", role: .destructive, action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Remove the recorded track")
        }
    }

    /// "12.4 km · ↑ 760 m · highest 1,743 m · 6 h 15 m".
    private var summary: String {
        var parts = [Format.distance(track.lengthKm, model.rules.unitSystem)]
        if let ascent = track.ascentMetres, ascent >= 1 {
            parts.append("↑ \(Format.whole(ascent)) m")
        }
        if let highest = track.highestMetres {
            parts.append("highest \(Format.whole(highest)) m")
        }
        if let minutes = track.minutes {
            parts.append(Format.duration(minutes: minutes))
        }
        return parts.joined(separator: " · ")
    }
}

extension UTType {
    /// GPX, by its extension: systems that know it call it `com.topografix.gpx`.
    static let gpx = UTType(filenameExtension: "gpx", conformingTo: .xml) ?? .xml
}

/// A picked file's bytes, read inside its security scope as the sandbox requires.
func readSecurityScoped(_ url: URL) -> Data? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
        if scoped {
            url.stopAccessingSecurityScopedResource()
        }
    }
    return try? Data(contentsOf: url)
}
