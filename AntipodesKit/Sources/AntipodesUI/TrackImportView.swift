import AntipodesCore
import AntipodesImport
import SwiftUI
import UniformTypeIdentifiers

/// One hike or ride found in a GPX file or Apple Health, before it is logged.
struct TrackCandidate: Identifiable {
    let id = UUID()
    var title: String
    var activity: HumanActivity
    var start: Date?
    var track: RecordedTrack?
    var origin: PlaceReference?
    var destination: PlaceReference?
    var include = true
    /// A leg with a track recorded at the same moment is already in the log.
    var isDuplicate = false
    /// For a workout whose route is read from Health only when it is added.
    var healthWorkout: UUID?
}

/// Brings in hikes, walks, runs and rides with the way they really went: GPX files from
/// any app or watch, and on iPhone the workouts Apple Health recorded (R-PATH-1, D-36).
/// Nothing is logged until the user has seen the list and said which to add.
struct TrackImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// A file already chosen, by dropping it on the Mac window.
    var file: Data?

    @State private var candidates: [TrackCandidate] = []
    @State private var isChoosingFiles = false
    @State private var isReading = false
    @State private var isAdding = false
    #if canImport(HealthKit) && os(iOS)
        @State private var health = HealthWorkouts()
    #endif

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Choose GPX Files…", systemImage: "doc.badge.plus") {
                        isChoosingFiles = true
                    }
                    #if canImport(HealthKit) && os(iOS)
                        if HealthWorkouts.isAvailable {
                            Button("From Apple Health", systemImage: "heart.text.square") {
                                Task { await readHealth() }
                            }
                        }
                    #endif
                } footer: {
                    Text("""
                    Each track becomes a hike, walk, run or ride, measured and drawn the way \
                    you went. Strava, Komoot, Garmin and AllTrails all export GPX.
                    """)
                }
                if isReading {
                    HStack {
                        ProgressView()
                        Text("Reading…").foregroundStyle(.secondary)
                    }
                }
                if !candidates.isEmpty {
                    Section {
                        ForEach($candidates) { $candidate in
                            TrackCandidateRow(candidate: $candidate)
                        }
                    } header: {
                        Text(Format.ordinalCount(candidates.count, "track"))
                    } footer: {
                        if candidates.contains(where: \.isDuplicate) {
                            Text("Tracks already in your log are left out unless you turn them on.")
                        }
                    }
                }
            }
            .navigationTitle("Import Hikes and Rides")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    let count = candidates.filter(\.include).count
                    Button(count == 0 ? "Add" : "Add \(count)") {
                        Task { await add() }
                    }
                    .disabled(count == 0 || isAdding)
                }
            }
            .fileImporter(
                isPresented: $isChoosingFiles,
                allowedContentTypes: [.gpx],
                allowsMultipleSelection: true
            ) { result in
                guard case let .success(urls) = result else { return }
                let files = urls.compactMap(readSecurityScoped)
                Task { await read(files) }
            }
            .task {
                if let file {
                    await read([file])
                }
            }
        }
        .interactiveDismissDisabled(candidates.contains(where: \.include))
        #if os(macOS)
            .frame(minWidth: 480, idealWidth: 540, minHeight: 480, idealHeight: 620)
        #endif
    }

    // MARK: - Reading

    private func read(_ files: [Data]) async {
        isReading = true
        defer { isReading = false }
        var found: [TrackCandidate] = []
        var unreadable = 0
        for data in files {
            guard let tracks = try? GPXReader.read(data) else {
                unreadable += 1
                continue
            }
            for track in tracks {
                guard let recorded = track.recordedTrack else { continue }
                await found.append(candidate(
                    title: track.name,
                    activity: track.activity,
                    start: track.start,
                    track: recorded
                ))
            }
        }
        candidates += found
        if unreadable > 0 {
            model.errorMessage = unreadable == 1
                ? "One file wasn't GPX or had no track in it."
                : "\(unreadable) files weren't GPX or had no track in them."
        }
    }

    private func candidate(
        title: String?,
        activity: HumanActivity,
        start: Date?,
        track: RecordedTrack?
    ) async -> TrackCandidate {
        var candidate = TrackCandidate(
            title: title ?? activity.displayName,
            activity: activity,
            start: start,
            track: track
        )
        if let track {
            (candidate.origin, candidate.destination) = await ends(
                of: track,
                named: candidate.title
            )
        }
        candidate.isDuplicate = isLogged(start)
        candidate.include = !candidate.isDuplicate
        return candidate
    }

    /// The town each end is in, or a pin there; a loop starts and ends at one place.
    private func ends(
        of track: RecordedTrack,
        named title: String
    ) async -> (PlaceReference?, PlaceReference?) {
        guard let first = track.points.first,
              let last = track.points.last else { return (nil, nil) }
        let origin = await place(at: first, name: "\(title) start")
        if GreatCircle.distanceKm(from: first, to: last) < 0.3 {
            return (origin, origin)
        }
        return await (origin, place(at: last, name: "\(title) end"))
    }

    private func place(at point: Coordinate, name: String) async -> PlaceReference {
        if let town = await model.nearestCity(to: point, withinKm: 10) {
            return town
        }
        return await model.resolvePin(at: point, name: name)
    }

    private func isLogged(_ start: Date?) -> Bool {
        guard let start else { return false }
        return model.log.allLegs.contains { leg in
            leg.recordedTrack?.start.map { abs($0.timeIntervalSince(start)) < 60 } ?? false
        }
    }

    // MARK: - Adding

    private func add() async {
        isAdding = true
        defer { isAdding = false }
        var legs: [JourneyLeg] = []
        for index in candidates.indices where candidates[index].include {
            #if canImport(HealthKit) && os(iOS)
                if candidates[index].track == nil, let workout = candidates[index].healthWorkout,
                   let track = try? await health.track(for: workout) {
                    candidates[index].track = track
                    (candidates[index].origin, candidates[index].destination) = await ends(
                        of: track,
                        named: candidates[index].title
                    )
                }
            #endif
            let candidate = candidates[index]
            guard let track = candidate.track, let origin = candidate.origin,
                  let destination = candidate.destination else { continue }
            legs.append(JourneyLeg(
                mode: .humanPowered,
                origin: origin,
                destination: destination,
                date: candidate.start.flatMap { CalendarDate($0) }
                    .map(FlexibleDate.day) ?? .unknown,
                activity: candidate.activity,
                recordedTrack: track
            ))
        }
        guard !legs.isEmpty else {
            model.errorMessage = "None of those tracks had a route to add."
            return
        }
        do {
            try model.importTracks(legs)
            model.announce("Added \(Format.ordinalCount(legs.count, "track"))")
            dismiss()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    #if canImport(HealthKit) && os(iOS)
        private func readHealth() async {
            isReading = true
            defer { isReading = false }
            do {
                let workouts = try await health.workouts()
                var found: [TrackCandidate] = []
                for workout in workouts {
                    var candidate = await candidate(
                        title: workout.activity.displayName,
                        activity: workout.activity,
                        start: workout.start,
                        track: nil
                    )
                    candidate.healthWorkout = workout.id
                    found.append(candidate)
                }
                if found.isEmpty {
                    model.errorMessage = "Health has no hikes, walks, runs or rides with a route."
                }
                candidates += found
            } catch {
                model.errorMessage = "Apple Health couldn't be read: \(error.localizedDescription)"
            }
        }
    #endif
}

/// A track to add or leave out.
private struct TrackCandidateRow: View {
    @Environment(AppModel.self) private var model
    @Binding var candidate: TrackCandidate

    var body: some View {
        Toggle(isOn: $candidate.include) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let route {
                        Text(route)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: candidate.activity.symbolName)
            }
        }
    }

    /// "2 Jul 2024 · 14.2 km · ↑ 760 m", and "Already logged" where it is.
    private var detail: String {
        var parts: [String] = []
        if let start = candidate.start {
            parts.append(start.formatted(date: .abbreviated, time: .omitted))
        }
        if let track = candidate.track {
            parts.append(Format.distance(track.lengthKm, model.rules.unitSystem))
            if let ascent = track.ascentMetres, ascent >= 1 {
                parts.append("↑ \(Format.whole(ascent)) m")
            }
        }
        if candidate.isDuplicate {
            parts.append("Already logged")
        }
        return parts.joined(separator: " · ")
    }

    private var route: String? {
        guard let origin = candidate.origin else { return nil }
        guard let destination = candidate.destination, destination.id != origin.id else {
            return "A loop from \(origin.name)"
        }
        return "\(origin.name) → \(destination.name)"
    }
}
