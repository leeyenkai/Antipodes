import AntipodesCore
import AntipodesGlobe
import SwiftUI

/// A bubble of the globe's photo layer, opened: the photos taken there, newest first,
/// the town they are nearest, and a way to log the visit they show (R-PHOTO-4, R-PHOTO-5).
struct PhotoClusterCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let cluster: PhotoCluster
    /// Logs a visit once this sheet has gone, as the globe's other cards do.
    let logVisit: (AddRequest) -> Void

    @State private var photos: [PhotoReference] = []
    @State private var place: PlaceReference?
    @State private var viewing: PhotoViewerStart?

    /// A city's worth of photos is thousands; the newest are the ones worth a glance.
    private static let shown = 120

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place?.name ?? "Photos taken here")
                            .font(.sectionTitle)
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            Button {
                                viewing = PhotoViewerStart(index: index)
                            } label: {
                                PhotoThumbnail(identifier: photo.localIdentifier, side: 84)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(photo.accessibilityName)
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    if cluster.count > Self.shown {
                        Text("The newest \(Self.shown) of \(cluster.count.formatted()).")
                    }
                }
                if let place {
                    Section {
                        Button("Log a Visit to \(place.name)", systemImage: "plus") {
                            logVisit(AddRequest(start: .place(place), date: dates))
                        }
                    } footer: {
                        Text("The dates are filled in from when these photos were taken.")
                    }
                }
            }
            .navigationTitle("Photos")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", role: .cancel) { dismiss() }
                }
            }
        }
        .task(id: cluster.id) {
            let wanted = Set(cluster.photoIDs.prefix(Self.shown))
            let dates = Dictionary(
                (model.photos.located ?? []).lazy
                    .filter { wanted.contains($0.id) }
                    .map { ($0.id, $0.takenAt) },
                uniquingKeysWith: { first, _ in first }
            )
            photos = cluster.photoIDs.prefix(Self.shown).map { id in
                PhotoReference(localIdentifier: id, takenAt: dates[id].flatMap(\.self))
            }
            place = await model.nearestCity(to: cluster.coordinate, withinKm: 25)
        }
        .sheet(item: $viewing) { start in
            PhotoViewer(photos: photos, start: start.index)
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 480, minHeight: 480, idealHeight: 620)
        #endif
    }

    /// "214 photos · 3 Jun 2023 – 12 Aug 2024".
    private var summary: String {
        var parts = [Format.ordinalCount(cluster.count, "photo")]
        if let first = cluster.first, let last = cluster.last {
            let start = first.formatted(date: .abbreviated, time: .omitted)
            let end = last.formatted(date: .abbreviated, time: .omitted)
            parts.append(start == end ? start : "\(start) – \(end)")
        }
        return parts.joined(separator: " · ")
    }

    /// The days the photos span, for the visit's date.
    private var dates: FlexibleDate? {
        guard let first = cluster.first.flatMap({ CalendarDate($0) }),
              let last = cluster.last.flatMap({ CalendarDate($0) }) else { return nil }
        return first == last ? .day(first) : .span(first, last)
    }
}

/// Reads where the library's photos were taken while the photo layer is on, asking for
/// access the first time; switches the layer off again if access is refused.
private struct PhotoLayerLoading: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.task(id: model.showsPhotoLayer) {
            guard model.showsPhotoLayer else { return }
            if !model.photos.canRead {
                guard await model.photos.requestAccess() else {
                    model.showsPhotoLayer = false
                    model.errorMessage = """
                    The photo layer needs access to your photos. You can allow it in \
                    Settings, under Privacy & Security, Photos.
                    """
                    return
                }
            }
            if model.photos.clusters == nil {
                await model.photos.loadLocatedPhotos()
            }
        }
    }
}

extension View {
    func photoLayerLoading() -> some View {
        modifier(PhotoLayerLoading())
    }
}

/// The photo layer's switch and what it currently shows, for the globe's style menu.
struct PhotoLayerToggle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            Toggle(
                "Show Photos",
                systemImage: "photo.on.rectangle.angled",
                isOn: $model.showsPhotoLayer
            )
            if model.showsPhotoLayer {
                if model.photos.isScanning {
                    Text("Reading where your photos were taken…")
                } else if let clusters = model.photos.clusters {
                    Text("\(Format.ordinalCount(clusters.photoCount, "photo")) with a location")
                }
                if model.photos.access == .limited {
                    Text("Only the photos you chose are shown.")
                }
            }
        } footer: {
            Text("Read on this device; nothing is stored or uploaded.")
        }
    }
}

// MARK: - Drawing

extension GlobeCanvas {
    /// Each group of photos as a bubble with its count, above the pins: a photo layer
    /// the user turned on is what they are looking at (R-PHOTO-4).
    func drawPhotoClusters(in context: inout GraphicsContext, globe: OrthographicGlobe) {
        for cluster in photoClusters {
            let projected = globe.project(cluster.coordinate)
            guard projected.isVisible else { continue }
            let isSelected = cluster.id == selectedPhotoCluster
            let radius = PhotoClusters.bubbleRadius(cluster.count) + (isSelected ? 2 : 0)
            let bubble = Path(ellipseIn: CGRect(
                x: projected.point.x - radius,
                y: projected.point.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.fill(bubble, with: .color(palette.photoBubble.opacity(isSelected ? 1 : 0.92)))
            context.stroke(
                bubble,
                with: .color(isSelected ? palette.visitedPin : palette.pinOutline),
                lineWidth: isSelected ? 2 : 1
            )
            context.draw(
                Text(Format.compactCount(cluster.count))
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(palette.photoBubbleText),
                at: CGPoint(x: projected.point.x, y: projected.point.y)
            )
        }
    }
}
