import AntipodesCore
import PhotosUI
import SwiftUI

/// A trip's photos: those linked to the trip and to its visits, in one grid, with a way
/// to add more and the photos taken on the trip offered for linking (R-PHOTO-1 to 3).
struct TripPhotosSection: View {
    @Environment(AppModel.self) private var model
    let trip: Trip
    let visits: [Visit]

    @State private var picked: [PhotosPickerItem] = []
    @State private var suggestions: [PhotoReference] = []
    @State private var viewing: PhotoViewerStart?

    private var photos: [PhotoReference] {
        (trip.photos + visits.flatMap(\.photos)).normalised()
    }

    var body: some View {
        Section {
            if !photos.isEmpty {
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
                PhotoSuggestions(
                    suggestions: suggestions,
                    caption: "Taken on this trip"
                ) { chosen in
                    link(chosen)
                }
            }
        } header: {
            Text("Photos")
        } footer: {
            if photos.isEmpty || model.photos.access != .full {
                PhotoAccessFooter()
            }
        }
        .onChange(of: picked) {
            let identifiers = picked.compactMap(\.itemIdentifier)
            guard !identifiers.isEmpty else { return }
            picked = []
            Task {
                if !model.photos.canRead {
                    await model.photos.requestAccess()
                }
                await link(model.photos.references(for: identifiers))
            }
        }
        .task(id: suggestionKey) {
            guard model.photos.canRead,
                  let dates = model.dates(ofTrip: trip.id) else {
                suggestions = []
                return
            }
            suggestions = await model.photos.suggestions(
                near: visits.compactMap(\.place.coordinate),
                during: .span(dates.start, dates.end),
                excluding: Set(photos.map(\.localIdentifier))
            )
        }
        .sheet(item: $viewing) { start in
            PhotoViewer(photos: photos, start: start.index, onRemove: unlink)
        }
    }

    private var suggestionKey: String {
        "\(trip.id)#\(photos.count)#\(visits.count)#\(model.photos.revision)#\(model.photos.access)"
    }

    /// Photos added here belong to the trip as a whole.
    private func link(_ chosen: [PhotoReference]) {
        guard !chosen.isEmpty else { return }
        var edited = trip
        edited.photos = (trip.photos + chosen).normalised()
        model.updateTrip(edited)
        let added = Set(chosen.map(\.localIdentifier))
        suggestions.removeAll { added.contains($0.localIdentifier) }
    }

    /// Unlinks a photo from whichever record holds it: the trip or one of its visits.
    private func unlink(_ photo: PhotoReference) {
        if trip.photos.contains(where: { $0.localIdentifier == photo.localIdentifier }) {
            var edited = trip
            edited.photos.removeAll { $0.localIdentifier == photo.localIdentifier }
            model.updateTrip(edited)
        }
        let holders = visits.filter { visit in
            visit.photos.contains { $0.localIdentifier == photo.localIdentifier }
        }
        let edited = holders.map { visit in
            var visit = visit
            visit.photos.removeAll { $0.localIdentifier == photo.localIdentifier }
            return visit
        }
        if !edited.isEmpty {
            model.updateVisits(edited)
        }
    }
}
