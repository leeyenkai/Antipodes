import AntipodesCore
import AntipodesGlobe
import SwiftUI

/// Drops a pin for somewhere the database does not have (R-LOG-5).
///
/// The globe turns under a fixed crosshair, and the place under it is resolved to a
/// country from the bundled borders as it moves — no geocoding service, no network,
/// nothing about the pin leaves the device (M1 acceptance criterion 3).
struct PinDropView: View {
    @Environment(AppModel.self) private var model

    let onContinue: (PlaceReference) -> Void

    @State private var borderStore = GlobeBorderStore()
    @State private var camera: GlobeCamera
    @GestureState private var dragTranslation: CGSize = .zero
    @State private var dragStart: GlobeCamera?
    @State private var zoomStart: Double?
    @State private var name = ""
    @State private var resolved: PlaceReference?
    @State private var isEnteringCoordinates = false
    @State private var latitudeText = ""
    @State private var longitudeText = ""

    init(initial: Coordinate?, onContinue: @escaping (PlaceReference) -> Void) {
        self.onContinue = onContinue
        _camera = State(initialValue: GlobeCamera(
            centre: initial ?? GlobeCamera.default.centre,
            zoom: initial == nil ? 1.4 : 8
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack {
                    GlobeCanvas(
                        scene: .empty,
                        borders: borderStore.borders(forZoom: liveCamera(in: proxy.size).zoom),
                        camera: liveCamera(in: proxy.size),
                        selection: nil,
                        palette: GlobePalette()
                    )
                    Crosshair()
                }
                .contentShape(.rect)
                .gesture(drag(in: proxy.size))
                .simultaneousGesture(zoom)
            }
            .background(Palette.space)
            .clipped()
            .accessibilityElement()
            .accessibilityLabel("Globe. Drag to move the pin, pinch to zoom.")
            .accessibilityValue(camera.centre.displayText)

            panel
        }
        .navigationTitle("Drop a Pin")
        .toolbarTitleDisplayMode(.inline)
        .onAppear { borderStore.loadCoarse() }
        .task(id: camera.centre) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            resolved = await model.resolvePin(at: camera.centre, name: name)
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(resolved?.flag ?? "📍").font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text(resolvedTitle)
                        .font(.headline)
                    Text(camera.centre.displayText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Coordinates", systemImage: "number") { isEnteringCoordinates = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
            }
            TextField("Name this place", text: $name)
                .capitalizingWords()
                .textFieldStyle(.roundedBorder)
            Button {
                Task {
                    let place = await model.resolvePin(
                        at: camera.centre,
                        name: name.trimmingCharacters(in: .whitespaces)
                    )
                    onContinue(place)
                }
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            if resolved?.countryCode == nil {
                CaveatLabel(text: "No country here, so this pin won't count towards coverage.")
            }
        }
        .padding(16)
        .background(.background)
        .alert("Enter Coordinates", isPresented: $isEnteringCoordinates) {
            TextField("Latitude, e.g. 59.91", text: $latitudeText)
                .decimalKeyboard()
            TextField("Longitude, e.g. 10.75", text: $longitudeText)
                .decimalKeyboard()
            Button("Cancel", role: .cancel) {}
            Button("Go") {
                if let latitude = Double(latitudeText.replacingOccurrences(of: ",", with: ".")),
                   let longitude = Double(longitudeText.replacingOccurrences(of: ",", with: ".")),
                   let coordinate = Coordinate(validating: latitude, longitude) {
                    withAnimation(.smooth) {
                        camera = GlobeCamera(centre: coordinate, zoom: max(camera.zoom, 8))
                    }
                }
            }
        } message: {
            Text("Decimal degrees. South and west are negative.")
        }
    }

    private var resolvedTitle: String {
        guard let resolved else { return "Locating…" }
        guard let country = resolved.countryName else { return "Open water or unclaimed land" }
        if let region = resolved.regionName {
            return "\(region), \(country)"
        }
        return country
    }

    private func liveCamera(in size: CGSize) -> GlobeCamera {
        guard dragTranslation != .zero else { return camera }
        return (dragStart ?? camera).dragged(
            dx: dragTranslation.width,
            dy: dragTranslation.height,
            in: GlobeSize(width: size.width, height: size.height)
        )
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($dragTranslation) { value, state, _ in state = value.translation }
            .onChanged { _ in
                if dragStart == nil {
                    dragStart = camera
                }
            }
            .onEnded { value in
                camera = (dragStart ?? camera).dragged(
                    dx: value.translation.width,
                    dy: value.translation.height,
                    in: GlobeSize(width: size.width, height: size.height)
                )
                dragStart = nil
            }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = zoomStart ?? camera.zoom
                zoomStart = base
                camera = GlobeCamera(centre: camera.centre, zoom: base * value.magnification)
            }
            .onEnded { _ in zoomStart = nil }
    }
}

/// The fixed marker the globe turns under.
private struct Crosshair: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: 2)
                .frame(width: 26, height: 26)
            Circle()
                .fill(Palette.pin)
                .frame(width: 8, height: 8)
            Rectangle().fill(.white.opacity(0.7)).frame(width: 1, height: 44)
            Rectangle().fill(.white.opacity(0.7)).frame(width: 44, height: 1)
        }
        .shadow(color: .black.opacity(0.6), radius: 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
