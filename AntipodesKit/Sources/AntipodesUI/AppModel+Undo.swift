import AntipodesCore
import Foundation

public extension AppModel {
    /// Records just deleted, held as values so they can be put back exactly — by the
    /// same identity, so nothing that pointed at them is broken.
    struct Deletion: Identifiable {
        public let id = UUID()
        public let message: String
        let records: TravelLog
        /// A trip deleted with its contents kept: what to file back under it.
        var refile: (trip: UUID, visits: [UUID], journeys: [UUID])?
    }

    /// A short confirmation, shown for a few seconds.
    struct Notice: Identifiable {
        public let id = UUID()
        public let message: String
        public var systemImage = "checkmark.circle"
    }

    func announce(_ message: String, systemImage: String = "checkmark.circle") {
        notice = Notice(message: message, systemImage: systemImage)
    }

    func offerUndo(_ deletion: Deletion) {
        lastDeletion = deletion
    }

    /// Puts the last deletion back.
    func undoLastDeletion() {
        guard let deletion = lastDeletion else { return }
        lastDeletion = nil
        perform {
            try store.merge(deletion.records)
            if let refile = deletion.refile {
                try store.moveVisits(refile.visits, toTrip: refile.trip)
                try store.moveJourneys(refile.journeys, toTrip: refile.trip)
            }
        }
    }
}
