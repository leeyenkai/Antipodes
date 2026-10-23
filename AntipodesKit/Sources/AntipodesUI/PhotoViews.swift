import AntipodesCore
import PhotosUI
import SwiftUI

/// A linked photo's thumbnail, asked of the library as it appears (D-35).
struct PhotoThumbnail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    let identifier: String
    var side: CGFloat = 76

    @State private var image: CGImage?
    @State private var isMissing = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.chip)
                .fill(.quaternary)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else if isMissing {
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Radius.chip))
        .task(id: "\(identifier)#\(model.photos.revision)") {
            image = await model.photos.thumbnail(identifier, side: side * displayScale)
            isMissing = image == nil
        }
        .accessibilityHidden(true)
    }
}

/// A record's photos in a row; a tap opens one full screen (R-PHOTO-1).
struct PhotoStrip: View {
    let photos: [PhotoReference]
    var side: CGFloat = 76
    let open: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    Button {
                        open(index)
                    } label: {
                        PhotoThumbnail(identifier: photo.localIdentifier, side: side)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(photo.accessibilityName)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 0)
    }
}

/// Which photo a viewer opens on.
struct PhotoViewerStart: Identifiable {
    let index: Int
    var id: Int {
        index
    }
}

/// The Photos section of a visit's form: what is linked, a picker to add more, and
/// the photos taken there on the visit's days, one tap each to add (R-PHOTO-1, R-PHOTO-2).
struct LinkedPhotosSection: View {
    @Environment(AppModel.self) private var model
    @Binding var photos: [PhotoReference]
    /// Where and when the record was, for suggestions; `nil` offers none.
    let around: (coordinate: Coordinate, date: FlexibleDate)?
    /// The photo opened full screen. The form presents the viewer: a sheet hung on a
    /// section inside a form can take the form's own sheet down with it.
    @Binding var viewing: PhotoViewerStart?

    @State private var picked: [PhotosPickerItem] = []
    @State private var suggestions: [PhotoReference] = []

    var body: some View {
        Section {
            if !photos.isEmpty {
                PhotoStrip(photos: photos) { viewing = PhotoViewerStart(index: $0) }
            }
            PhotosPicker(
                selection: $picked,
                matching: .images,
                preferredItemEncoding: .current,
                photoLibrary: .shared()
            ) {
                Label("Add Photos", systemImage: "photo.badge.plus")
            }
            if !suggestions.isEmpty {
                PhotoSuggestions(suggestions: suggestions) { chosen in
                    photos = (photos + chosen).normalised()
                    let added = Set(chosen.map(\.localIdentifier))
                    suggestions.removeAll { added.contains($0.localIdentifier) }
                }
            }
        } header: {
            Text("Photos")
        } footer: {
            PhotoAccessFooter()
        }
        .onChange(of: picked) {
            let identifiers = picked.compactMap(\.itemIdentifier)
            guard !identifiers.isEmpty else { return }
            picked = []
            Task {
                if !model.photos.canRead {
                    await model.photos.requestAccess()
                }
                let references = await model.photos.references(for: identifiers)
                photos = (photos + references).normalised()
            }
        }
        .task(id: suggestionKey) {
            guard let around, model.photos.canRead else {
                suggestions = []
                return
            }
            suggestions = await model.photos.suggestions(
                near: [around.coordinate],
                during: around.date,
                excluding: Set(photos.map(\.localIdentifier))
            )
        }
    }

    private var suggestionKey: String {
        guard let around else { return "" }
        return "\(around.coordinate.latitude),\(around.coordinate.longitude),"
            + "\(around.date.exportString),\(model.photos.revision),\(model.photos.access)"
    }
}

/// The photos taken at a place on a record's days, offered for linking.
struct PhotoSuggestions: View {
    let suggestions: [PhotoReference]
    var caption = "Taken here on these days"
    let add: ([PhotoReference]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if suggestions.count > 1 {
                    Button("Add All \(suggestions.count)") { add(suggestions) }
                        .font(.subheadline)
                }
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(suggestions) { photo in
                        Button {
                            add([photo])
                        } label: {
                            PhotoThumbnail(identifier: photo.localIdentifier, side: 60)
                                .opacity(0.85)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "plus.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .tint)
                                        .padding(4)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(photo.accessibilityName)")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, 2)
    }
}

/// What the library lets Antipodes see, and the promise that nothing is copied.
struct PhotoAccessFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.photos.access {
        case .limited:
            Text("""
            Antipodes can see only the photos you chose. Allow access to all photos in \
            Settings to see every linked photo and suggestions.
            """)
        case .denied:
            Text("Photos access is off. Turn it on in Settings to see linked photos.")
        default:
            Text("Photos stay in your library. Antipodes links to them and never copies them.")
        }
    }
}

/// Photos one at a time, as large as the screen allows, with Remove where the record
/// can be edited (R-PHOTO-1). Removing unlinks the photo; the library keeps it.
struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let photos: [PhotoReference]
    let onRemove: ((PhotoReference) -> Void)?

    @State private var page: Int

    init(photos: [PhotoReference], start: Int, onRemove: ((PhotoReference) -> Void)? = nil) {
        self.photos = photos
        self.onRemove = onRemove
        _page = State(initialValue: min(max(0, start), max(0, photos.count - 1)))
    }

    var body: some View {
        NavigationStack {
            Group {
                if photos.isEmpty {
                    ContentUnavailableView("No photos", systemImage: "photo")
                } else {
                    Pager(page: $page, count: photos.count) { index in
                        FullPhoto(identifier: photos[index].localIdentifier)
                    }
                }
            }
            .background(Color.black)
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", role: .cancel) { dismiss() }
                }
                if let onRemove, photos.indices.contains(page) {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Remove Photo", systemImage: "minus.circle", role: .destructive) {
                            onRemove(photos[page])
                            dismiss()
                        }
                        .help("Unlink this photo. It stays in your library.")
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, idealWidth: 860, minHeight: 520, idealHeight: 700)
        #endif
    }

    private var title: String {
        guard photos.indices.contains(page), let taken = photos[page].takenAt else {
            return "Photo"
        }
        return taken.formatted(date: .abbreviated, time: .shortened)
    }
}

/// One photo, fitted to the space, fetched at a size worth looking at.
private struct FullPhoto: View {
    @Environment(AppModel.self) private var model
    let identifier: String

    @State private var image: CGImage?
    @State private var isMissing = false

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else if isMissing {
                ContentUnavailableView(
                    "Photo not found",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("It may have been deleted from your library.")
                )
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: identifier) {
            image = await model.photos.image(identifier, maxSide: 2400)
            isMissing = image == nil
        }
    }
}

extension PhotoReference {
    /// "Photo taken 12 June 2024", for VoiceOver.
    var accessibilityName: String {
        takenAt.map { "Photo taken \($0.formatted(date: .long, time: .omitted))" } ?? "Photo"
    }
}
