import AntipodesCore
import AntipodesGlobe
import Foundation
import SwiftUI
#if canImport(Photos)
    import Photos
#endif
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// A geotagged photo in the library, for the globe's photo layer (R-PHOTO-4). Read on
/// the device when the layer is on, held in memory, and never stored (D-35).
struct LibraryPhoto: Sendable, Hashable {
    let id: String
    let coordinate: Coordinate
    let takenAt: Date?
}

/// The app's window on the Photos library: access, thumbnails, the photos taken around
/// a visit, and where every photo was taken (R-PHOTO-1 to 5, D-35).
///
/// Photos are linked, never copied: a record keeps a `PhotoReference`, and everything
/// here is asked of the library when it is shown. A photo deleted from the library is
/// skipped quietly wherever it was linked.
@MainActor
@Observable
final class PhotoLibrary {
    enum Access: Equatable {
        case notAsked
        case full
        /// The user chose some photos only; linked photos outside the choice don't show.
        case limited
        case denied
        /// This platform has no photo library.
        case unavailable
    }

    private(set) var access: Access = .notAsked
    /// Bumped when the library changes, so photo views and the globe layer reload.
    private(set) var revision = 0
    /// Every photo with a location, once `loadLocatedPhotos` has run.
    private(set) var located: [LibraryPhoto]?
    /// Those photos grouped for the globe at every zoom band.
    private(set) var clusters: PhotoClusters?
    private(set) var isScanning = false

    @ObservationIgnored private var thumbnails: [String: CGImage] = [:]
    @ObservationIgnored private var thumbnailOrder: [String] = []
    private static let thumbnailLimit = 600
    #if canImport(Photos)
        @ObservationIgnored private var observer: ChangeObserver?
    #endif

    init() {
        #if canImport(Photos)
            access = Self.access(PHPhotoLibrary.authorizationStatus(for: .readWrite))
            if access == .full || access == .limited {
                startObserving()
            }
        #else
            access = .unavailable
        #endif
    }

    var canRead: Bool {
        access == .full || access == .limited
    }

    /// Asks for access the first time; afterwards says what the user chose.
    @discardableResult
    func requestAccess() async -> Bool {
        #if canImport(Photos)
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            access = Self.access(status)
            if canRead {
                startObserving()
            }
            return canRead
        #else
            return false
        #endif
    }

    // MARK: - References

    /// References for photos the user just chose, with when and where each was taken
    /// and the identifier another device would know it by.
    func references(for identifiers: [String]) async -> [PhotoReference] {
        #if canImport(Photos)
            guard !identifiers.isEmpty else { return [] }
            return await Task.detached(priority: .userInitiated) {
                Self.makeReferences(identifiers)
            }.value
        #else
            return []
        #endif
    }

    /// The photos in a list that are still in the library, in the same order.
    func available(_ photos: [PhotoReference]) -> [PhotoReference] {
        #if canImport(Photos)
            guard canRead, !photos.isEmpty else { return canRead ? [] : photos }
            let found = PHAsset.fetchAssets(
                withLocalIdentifiers: photos.map(\.localIdentifier),
                options: nil
            )
            var present = Set<String>()
            found.enumerateObjects { asset, _, _ in present.insert(asset.localIdentifier) }
            return photos.filter { present.contains($0.localIdentifier) }
        #else
            return photos
        #endif
    }

    /// A restored backup's photos, re-pointed at this device's library where iCloud
    /// Photos knows them by another identifier (D-35). Photos it cannot find keep their
    /// old identifiers, so a later restore on the original device still finds them.
    func reconcile(_ log: TravelLog) -> TravelLog {
        #if canImport(Photos)
            guard canRead else { return log }
            let all = log.visits.flatMap(\.photos) + log.trips.flatMap(\.photos)
            let missing = Set(all.map(\.localIdentifier)).subtracting(
                Set(available(all).map(\.localIdentifier))
            )
            let clouds = all.filter { missing.contains($0.localIdentifier) }
                .compactMap(\.cloudIdentifier)
            guard !clouds.isEmpty else { return log }
            let mappings = PHPhotoLibrary.shared().localIdentifierMappings(
                for: clouds.map { PHCloudIdentifier(stringValue: $0) }
            )
            var local: [String: String] = [:]
            for (cloud, result) in mappings {
                if case let .success(identifier) = result {
                    local[cloud.stringValue] = identifier
                }
            }
            func remap(_ photos: [PhotoReference]) -> [PhotoReference] {
                photos.map { photo in
                    guard missing.contains(photo.localIdentifier),
                          let cloud = photo.cloudIdentifier,
                          let identifier = local[cloud] else { return photo }
                    var moved = photo
                    moved.localIdentifier = identifier
                    return moved
                }
            }
            var result = log
            result.visits = log.visits.map { visit in
                var visit = visit
                visit.photos = remap(visit.photos)
                return visit
            }
            result.trips = log.trips.map { trip in
                var trip = trip
                trip.photos = remap(trip.photos)
                return trip
            }
            return result
        #else
            return log
        #endif
    }

    // MARK: - Pictures

    /// A square thumbnail, from memory when it was shown recently.
    func thumbnail(_ identifier: String, side: CGFloat) async -> CGImage? {
        let key = "\(identifier)#\(Int(side))"
        if let cached = thumbnails[key] {
            return cached
        }
        guard let image = await picture(
            identifier,
            size: CGSize(width: side, height: side),
            fill: true
        )
        else { return nil }
        thumbnails[key] = image
        thumbnailOrder.append(key)
        if thumbnailOrder.count > Self.thumbnailLimit {
            thumbnails[thumbnailOrder.removeFirst()] = nil
        }
        return image
    }

    /// The photo at a size for viewing, fetched from iCloud if it is not on the device.
    func image(_ identifier: String, maxSide: CGFloat) async -> CGImage? {
        await picture(identifier, size: CGSize(width: maxSide, height: maxSide), fill: false)
    }

    private func picture(_ identifier: String, size: CGSize, fill: Bool) async -> CGImage? {
        #if canImport(Photos)
            guard canRead,
                  let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
                  .firstObject else { return nil }
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            return await withCheckedContinuation { continuation in
                PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: size,
                    contentMode: fill ? .aspectFill : .aspectFit,
                    options: options
                ) { image, _ in
                    continuation.resume(returning: image?.cgImageValue)
                }
            }
        #else
            return nil
        #endif
    }

    // MARK: - Finding photos

    /// Photos taken within `radiusKm` of any of these places during a record's dates,
    /// oldest first — the ones a visit or a trip most likely wants (R-PHOTO-2). Nothing
    /// for an undated record.
    func suggestions(
        near places: [Coordinate],
        during date: FlexibleDate,
        excluding linked: Set<String>,
        radiusKm: Double = 25
    ) async -> [PhotoReference] {
        #if canImport(Photos)
            guard canRead, !places.isEmpty,
                  let first = date.earliestDay?.date(in: .current),
                  let last = date.latestDay?.adding(days: 1)?.date(in: .current)
            else { return [] }
            return await Task.detached(priority: .userInitiated) {
                Self.photos(from: first, to: last).filter { photo in
                    guard !linked.contains(photo.localIdentifier),
                          let taken = photo.coordinate else { return false }
                    return places.contains {
                        GreatCircle.distanceKm(from: $0, to: taken) <= radiusKm
                    }
                }
            }.value
        #else
            return []
        #endif
    }

    /// Reads where every photo in the library was taken, for the globe's photo layer
    /// (R-PHOTO-4). Runs once, again when the library changes, and keeps nothing on disk.
    func loadLocatedPhotos() async {
        #if canImport(Photos)
            guard canRead, !isScanning else { return }
            isScanning = true
            let revision = revision
            let (photos, grouped) = await Task.detached(priority: .utility) {
                let photos = Self.allLocated()
                let points = photos.map {
                    PhotoPoint(id: $0.id, coordinate: $0.coordinate, takenAt: $0.takenAt)
                }
                return (photos, PhotoClusters(points))
            }.value
            // A change arrived while reading: read again rather than show a stale layer.
            if revision == self.revision {
                located = photos
                clusters = grouped
            }
            isScanning = false
            if revision != self.revision {
                await loadLocatedPhotos()
            }
        #endif
    }

    // MARK: - Library access, off the main actor

    #if canImport(Photos)
        private static func access(_ status: PHAuthorizationStatus) -> Access {
            switch status {
            case .authorized: .full
            case .limited: .limited
            case .notDetermined: .notAsked
            default: .denied
            }
        }

        private func startObserving() {
            guard observer == nil else { return }
            let observer = ChangeObserver { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.revision += 1
                    self.thumbnails.removeAll()
                    self.thumbnailOrder.removeAll()
                    if self.located != nil {
                        await self.loadLocatedPhotos()
                    }
                }
            }
            PHPhotoLibrary.shared().register(observer)
            self.observer = observer
        }

        nonisolated static func makeReferences(_ identifiers: [String])
            -> [PhotoReference] {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            var byID: [String: PHAsset] = [:]
            assets.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
            let clouds = PHPhotoLibrary.shared().cloudIdentifierMappings(
                forLocalIdentifiers: Array(byID.keys)
            )
            return identifiers.map { identifier in
                // Outside a limited selection the library will not say more than the
                // identifier; link it anyway, so it shows once access is widened.
                guard let asset = byID[identifier] else {
                    return PhotoReference(localIdentifier: identifier)
                }
                let cloud = try? clouds[identifier]?.get().stringValue
                return reference(asset, cloud: cloud)
            }
        }

        nonisolated static func reference(
            _ asset: PHAsset,
            cloud: String?
        ) -> PhotoReference {
            PhotoReference(
                localIdentifier: asset.localIdentifier,
                cloudIdentifier: cloud,
                takenAt: asset.creationDate,
                coordinate: asset.location.flatMap(coordinate)
            )
        }

        nonisolated static func coordinate(_ location: CLLocation) -> Coordinate? {
            let value = location.coordinate
            // Photos with no fix report (0, 0); nobody photographs Null Island.
            guard value.latitude != 0 || value.longitude != 0 else { return nil }
            return Coordinate(validating: value.latitude, value.longitude)
        }

        nonisolated static func photos(from start: Date, to end: Date) -> [PhotoReference] {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate < %@",
                start as NSDate,
                end as NSDate
            )
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            var result: [PhotoReference] = []
            PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
                result.append(reference(asset, cloud: nil))
            }
            return result
        }

        nonisolated static func allLocated() -> [LibraryPhoto] {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            var result: [LibraryPhoto] = []
            PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
                guard let location = asset.location,
                      let point = coordinate(location) else { return }
                result.append(LibraryPhoto(
                    id: asset.localIdentifier,
                    coordinate: point,
                    takenAt: asset.creationDate
                ))
            }
            return result
        }
    #endif
}

#if canImport(Photos)
    /// Tells the library wrapper when photos are added, edited or deleted.
    private final class ChangeObserver: NSObject, PHPhotoLibraryChangeObserver, Sendable {
        private let onChange: @Sendable () -> Void

        init(onChange: @escaping @Sendable () -> Void) {
            self.onChange = onChange
        }

        func photoLibraryDidChange(_: PHChange) {
            onChange()
        }
    }
#endif

#if os(iOS)
    extension UIImage {
        var cgImageValue: CGImage? {
            cgImage
        }
    }
#elseif os(macOS)
    extension NSImage {
        var cgImageValue: CGImage? {
            cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }
#endif
