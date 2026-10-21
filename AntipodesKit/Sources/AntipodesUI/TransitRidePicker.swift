import AntipodesCore
import AntipodesPlaces
import SwiftUI

/// A city transit ride as the picker returns it: the line and its two stops (R-JLOG-5).
struct TransitRide {
    let system: TransitSystemInfo
    let line: TransitLineInfo
    let origin: PlaceReference
    let destination: PlaceReference
    /// Stop to stop along the line: the leg's stored path length (R-PATH-5).
    let lengthKm: Double?
}

/// Pick the city, the system, the line, then the boarding and alighting stops
/// (R-JLOG-5). The systems come from the bundled transit packs (R-TRAN-5); a ride on a
/// system that is not there is logged between two places instead.
struct TransitRidePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onPick: (TransitRide) -> Void
    /// Logging between two places, for a system the packs do not have.
    let onPlacesInstead: () -> Void

    @State private var systems: [TransitSystemInfo] = []
    @State private var search = ""
    @State private var path: [Step] = []

    enum Step: Hashable {
        case lines(TransitSystemInfo)
        case stops(TransitSystemInfo, TransitLineInfo)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(filtered) { system in
                        NavigationLink(value: Step.lines(system)) {
                            TransitSystemRow(system: system)
                        }
                    }
                } footer: {
                    Text("""
                    Stations and lines from Wikidata. A system that isn't here can still be \
                    logged between two places.
                    """)
                }
                Section {
                    Button("Log Between Two Places Instead", systemImage: "mappin.and.ellipse") {
                        dismiss()
                        onPlacesInstead()
                    }
                }
            }
            .searchable(text: $search, prompt: "City or system")
            .navigationTitle("City Transit")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case let .lines(system):
                    TransitLineList(system: system)
                case let .stops(system, line):
                    TransitStopList(system: system, line: line) { ride in
                        onPick(ride)
                        dismiss()
                    }
                }
            }
            .task {
                systems = await (try? model.places?.transitSystems()) ?? []
            }
        }
    }

    private var filtered: [TransitSystemInfo] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return systems }
        return systems.filter { system in
            [system.name, system.cityName ?? "", Format.countryName(system.countryCode)]
                .contains { $0.lowercased().contains(query) }
        }
    }
}

/// A system's lines, with their colours.
private struct TransitLineList: View {
    @Environment(AppModel.self) private var model
    let system: TransitSystemInfo

    @State private var network: TransitNetwork?

    var body: some View {
        List {
            if let network {
                ForEach(lines(in: network)) { line in
                    NavigationLink(value: TransitRidePicker.Step.stops(system, line)) {
                        TransitLineLabel(line: line)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(system.name)
        .task {
            network = await model.transitNetwork(forSystem: system.id)
        }
    }

    private func lines(in network: TransitNetwork) -> [TransitLineInfo] {
        network.lines.values.filter { $0.systemID == system.id }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// A line's stops in riding order: tap where you got on, then where you got off.
private struct TransitStopList: View {
    @Environment(AppModel.self) private var model
    let system: TransitSystemInfo
    let line: TransitLineInfo
    let onPick: (TransitRide) -> Void

    @State private var network: TransitNetwork?
    @State private var boarding: Int64?
    @State private var isFinishing = false

    var body: some View {
        List {
            Section {
                ForEach(stops, id: \.self) { stop in
                    Button {
                        choose(stop)
                    } label: {
                        HStack {
                            Text(network?.stops[stop]?.name ?? "")
                                .foregroundStyle(.primary)
                            Spacer()
                            if stop == boarding {
                                Text("Got on")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(isFinishing)
                }
            } header: {
                Text(boarding == nil ? "Where did you get on?" : "Where did you get off?")
            }
        }
        .navigationTitle(line.name)
        .toolbar {
            if boarding != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Start Again") { boarding = nil }
                }
            }
        }
        .task {
            network = await model.transitNetwork(forSystem: system.id)
        }
        .sensoryFeedback(.selection, trigger: boarding)
    }

    private var stops: [Int64] {
        network?.orderedStops(ofLine: line.id) ?? []
    }

    private func choose(_ stop: Int64) {
        guard let boarding else {
            boarding = stop
            return
        }
        guard stop != boarding, let network else { return }
        isFinishing = true
        Task {
            guard let origin = await model.transitStopPlace(boarding),
                  let destination = await model.transitStopPlace(stop)
            else {
                isFinishing = false
                return
            }
            let path = network.route(onLine: line.id, from: boarding, to: stop)
            onPick(TransitRide(
                system: system,
                line: line,
                origin: origin,
                destination: destination,
                lengthKm: path.flatMap(network.lengthKm(of:))
            ))
        }
    }
}

/// A line's name with its colour.
struct TransitLineLabel: View {
    let line: TransitLineInfo

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(line.colour.flatMap(Color.init(hex:)) ?? Color.secondary.opacity(0.4))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(line.name)
            if let short = line.shortName, short != line.name {
                Text(short)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension Color {
    /// A colour from six hex digits, "DC241F".
    init?(hex: String) {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension AppModel {
    /// One system's network, for the picker.
    func transitNetwork(forSystem system: Int64) async -> TransitNetwork? {
        try? await places?.transitNetwork(systems: [system])
    }

    func transitStopPlace(_ stop: Int64) async -> PlaceReference? {
        try? await places?.transitStopPlace(id: stop)
    }
}

/// The line a city transit leg rode, or the way to choose one.
struct TransitLineButton: View {
    @Environment(AppModel.self) private var model
    let lineID: Int64?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LabeledContent("Line") {
                if let line = lineID
                    .flatMap({ model.transitNetwork.lines[$0] ?? pickedLines[$0] }) {
                    TransitLineLabel(line: line)
                } else if lineID != nil {
                    Text("Chosen line")
                } else {
                    Text("Choose a line and stops")
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: lineID) { await loadLine() }
    }

    /// A line just picked is not in the model's network until the ride is saved.
    @State private var pickedLines: [Int64: TransitLineInfo] = [:]

    private func loadLine() async {
        guard let lineID, model.transitNetwork.lines[lineID] == nil, pickedLines[lineID] == nil,
              let systems = try? await model.places?.transitSystems(ofLines: [lineID]),
              let network = try? await model.places?.transitNetwork(systems: systems),
              let line = network.lines[lineID]
        else { return }
        pickedLines[lineID] = line
    }
}

/// A system with where it runs.
private struct TransitSystemRow: View {
    let system: TransitSystemInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(system.name)
            Text(place)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var place: String {
        let country = Format.countryName(system.countryCode)
        guard let city = system.cityName else { return country }
        return "\(city), \(country)"
    }
}
