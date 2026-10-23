import AntipodesCore
@testable import AntipodesExport
import Foundation
import Testing

/// Photos are linked, never copied (D-35), so a backup carries the references and a
/// restore puts them back on the same records.
@Suite("Photo references in backups")
struct PhotoBackupTests {
    static let oslo = PlaceReference(
        id: .database(.city, 3_143_244),
        kind: .city,
        name: "Oslo",
        coordinate: Coordinate(latitude: 59.913, longitude: 10.752),
        countryCode: "NO"
    )

    static let harbour = PhotoReference(
        localIdentifier: "A1B2C3/L0/001",
        cloudIdentifier: "cloud-1",
        takenAt: Date(timeIntervalSince1970: 1_717_200_000),
        coordinate: Coordinate(latitude: 59.907, longitude: 10.735)
    )

    @Test("A visit's and a trip's photos survive a backup and restore")
    func roundTrip() throws {
        let trip = Trip(name: "Oslo weekend", photos: [Self.harbour])
        let visit = Visit(place: Self.oslo, tripID: trip.id, photos: [Self.harbour])
        let log = TravelLog(trips: [trip], visits: [visit])

        let restored = try TravelLogExport.importLog(fromJSON: TravelLogExport.json(for: log))
        #expect(restored.trips.first?.photos == [Self.harbour])
        #expect(restored.visits.first?.photos == [Self.harbour])
    }

    /// Every backup made before photos has no `photos` key at all.
    @Test("A version 3 backup restores with no photos rather than failing")
    func olderBackup() throws {
        let json = """
        {"formatVersion": 3, "application": "Antipodes", "exportedAt": "",
         "log": {"trips": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "name": "Rome"}],
                 "visits": [], "journeys": []}}
        """
        let restored = try TravelLogExport.importLog(fromJSON: Data(json.utf8))
        #expect(restored.trips.first?.name == "Rome")
        #expect(restored.trips.first?.photos == [])
    }

    @Test("A record's photos are ordered oldest first, each once, undated last")
    func ordering() {
        let early = PhotoReference(localIdentifier: "a", takenAt: Date(timeIntervalSince1970: 10))
        let late = PhotoReference(localIdentifier: "b", takenAt: Date(timeIntervalSince1970: 20))
        let undated = PhotoReference(localIdentifier: "c")
        #expect([undated, late, early, late].normalised().map(\.localIdentifier) == ["a", "b", "c"])
    }
}
