import AntipodesCore
import AntipodesExport
import Foundation

public extension AppModel {
    // MARK: - Export

    func exportJSON() throws -> Data {
        try TravelLogExport.json(for: log)
    }

    func exportCSVFiles() -> [String: Data] {
        TravelLogExport.csvFiles(for: log)
    }
}

/// A record to open from outside the app's own navigation — a widget's link — and the
/// tab whose list it opens in.
public struct PendingRoute: Equatable {
    public enum Tab: Equatable, Sendable {
        case trips
        case collections
    }

    public let id = UUID()
    let tab: Tab
    let route: LogRoute
}

extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
