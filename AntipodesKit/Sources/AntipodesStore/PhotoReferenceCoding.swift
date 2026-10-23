import AntipodesCore
import Foundation

/// How a record's linked photos are kept in one column (D-35).
///
/// A list of references is small and always read whole, so it is one encoded value
/// rather than a model of its own: adding the column is the additive, optional change
/// the schema's rules allow without a migration stage (see `StoredModels.swift`).
enum PhotoReferenceCoding {
    static func encode(_ photos: [PhotoReference]) -> Data? {
        photos.isEmpty ? nil : try? JSONEncoder().encode(photos)
    }

    /// A column that cannot be read gives no photos rather than failing the whole log.
    static func decode(_ data: Data?) -> [PhotoReference] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([PhotoReference].self, from: data)) ?? []
    }
}
