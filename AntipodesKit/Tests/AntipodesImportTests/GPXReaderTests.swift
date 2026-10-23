import AntipodesCore
@testable import AntipodesImport
import Foundation
import Testing

@Suite("GPX reading")
struct GPXReaderTests {
    static let hike = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="Test" xmlns="http://www.topografix.com/GPX/1/1">
      <trk>
        <name>Besseggen</name>
        <type>hiking</type>
        <trkseg>
          <trkpt lat="61.4945" lon="8.8110"><ele>984</ele><time>2024-07-02T07:00:00Z</time></trkpt>
          <trkpt lat="61.4990" lon="8.7900">
            <ele>1250</ele><time>2024-07-02T08:30:00.500Z</time>
          </trkpt>
        </trkseg>
        <trkseg>
          <trkpt lat="61.5030" lon="8.7700"><ele>1743</ele><time>2024-07-02T10:00:00Z</time></trkpt>
          <trkpt lat="61.5050" lon="8.7300"><ele>1100</ele><time>2024-07-02T13:15:00Z</time></trkpt>
        </trkseg>
      </trk>
    </gpx>
    """

    @Test("A track's segments join into one, with heights and times")
    func track() throws {
        let tracks = try GPXReader.read(Data(Self.hike.utf8))
        let track = try #require(tracks.first)
        #expect(tracks.count == 1)
        #expect(track.name == "Besseggen")
        #expect(track.points.count == 4)
        #expect(track.activity == .hike)
        #expect(track.start == ISO8601DateFormatter().date(from: "2024-07-02T07:00:00Z"))

        let recorded = try #require(track.recordedTrack)
        #expect(recorded.minutes == 375)
        #expect(recorded.highestMetres == 1743)
        #expect(abs((recorded.ascentMetres ?? 0) - 759) < 1)
        #expect(recorded.lengthKm > 4 && recorded.lengthKm < 6)
    }

    @Test("A route with no times reads too, and a ride is a ride")
    func route() throws {
        let gpx = """
        <gpx version="1.0"><rte><name>Morning Ride</name>
          <rtept lat="51.5" lon="-0.12"/><rtept lat="51.52" lon="-0.10"/>
        </rte></gpx>
        """
        let track = try #require(try GPXReader.read(Data(gpx.utf8)).first)
        #expect(track.activity == .cycle)
        #expect(track.start == nil)
        #expect(track.recordedTrack?.minutes == nil)
    }

    @Test("A file that is not GPX, or has no track, says so")
    func failures() {
        #expect(throws: GPXReader.Failure.notGPX) {
            try GPXReader.read(Data("date,from,to".utf8))
        }
        #expect(throws: GPXReader.Failure.noTracks) {
            try GPXReader.read(Data(#"<gpx><wpt lat="1" lon="2"/></gpx>"#.utf8))
        }
    }

    @Test("A recorded track survives a backup in compact form")
    func coding() throws {
        let track = try #require(try GPXReader.read(Data(Self.hike.utf8)).first?.recordedTrack)
        let data = try JSONEncoder().encode(track)
        #expect(data.count < 400)
        let back = try JSONDecoder().decode(RecordedTrack.self, from: data)
        #expect(back.points.count == track.points.count)
        #expect(abs(back.lengthKm - track.lengthKm) < 0.001)
        #expect(back.elevations == track.elevations)
    }

    @Test("A recorded track's length beats every figure but the user's own")
    func precedence() throws {
        let track = try #require(try GPXReader.read(Data(Self.hike.utf8)).first?.recordedTrack)
        let start = PlaceReference(
            id: .custom(UUID()),
            kind: .custom,
            name: "Gjendesheim",
            coordinate: track.points[0]
        )
        let end = PlaceReference(
            id: .custom(UUID()),
            kind: .custom,
            name: "Memurubu",
            coordinate: track.points[3]
        )
        var leg = JourneyLeg(
            mode: .humanPowered,
            origin: start,
            destination: end,
            storedPathLengthKm: 99,
            activity: .hike,
            recordedTrack: track
        )
        #expect(leg.distanceSource == .recordedTrack)
        #expect(leg.durationMinutes == 375)
        #expect(!leg.needsTrackMeasurement)
        leg.distanceKmOverride = 14
        #expect(leg.distanceSource == .userOverride)
        #expect(leg.trackKind == .hiking)
    }
}
