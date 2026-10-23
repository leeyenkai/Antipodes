import Foundation

/// A photo in the user's library, linked to a visit or a trip (R-PHOTO-1, D-35).
///
/// The photo itself is never copied: the log holds where to find it, and the app asks
/// the library for it when it is shown. A photo deleted from the library simply stops
/// appearing. The identifier is the library's own and only means something on this
/// device; the cloud identifier is what lets a restored backup find the same photo on
/// another device signed in to the same iCloud Photos.
public struct PhotoReference: Hashable, Sendable, Codable, Identifiable {
    /// The library's identifier for the photo on this device.
    public var localIdentifier: String
    /// The library's identifier for it across devices, where iCloud Photos gives one.
    public var cloudIdentifier: String?
    /// When the photo was taken, kept so a record can order and date its photos without
    /// asking the library.
    public var takenAt: Date?
    /// Where it was taken, if the photo says.
    public var coordinate: Coordinate?

    public var id: String {
        localIdentifier
    }

    public init(
        localIdentifier: String,
        cloudIdentifier: String? = nil,
        takenAt: Date? = nil,
        coordinate: Coordinate? = nil
    ) {
        self.localIdentifier = localIdentifier
        self.cloudIdentifier = cloudIdentifier
        self.takenAt = takenAt
        self.coordinate = coordinate
    }
}

public extension [PhotoReference] {
    /// Oldest first, undated last, each photo once — the order a record shows them in.
    func normalised() -> [PhotoReference] {
        var seen = Set<String>()
        let unique = filter { seen.insert($0.localIdentifier).inserted }
        return unique.enumerated().sorted { first, second in
            switch (first.element.takenAt, second.element.takenAt) {
            case let (a?, b?) where a != b: a < b
            case (_?, nil): true
            case (nil, _?): false
            default: first.offset < second.offset
            }
        }.map(\.element)
    }
}
