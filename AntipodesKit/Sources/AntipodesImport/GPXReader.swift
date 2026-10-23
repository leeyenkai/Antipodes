import AntipodesCore
import Foundation
#if canImport(FoundationXML)
    import FoundationXML
#endif

/// One track or route from a GPX file: what a GPS watch, Strava, Komoot, Garmin or
/// AllTrails exports for a hike or a ride (R-PATH-1, D-36).
public struct GPXTrack: Sendable, Hashable {
    public let name: String?
    /// The file's own word for the activity, where it has one: `hiking`, `cycling`, `9`.
    public let type: String?
    public let points: [Coordinate]
    public let elevations: [Double?]
    public let times: [Date?]

    public var start: Date? {
        times.compactMap(\.self).first
    }

    public var end: Date? {
        times.compactMap(\.self).last
    }

    /// The activity the file says it was, by its type or its name; a hike if neither
    /// says, since that is what a trail recording most often is.
    public var activity: HumanActivity {
        let words = [type, name].compactMap { $0?.lowercased() }.joined(separator: " ")
        if words.contains("cycl") || words.contains("bik") || words.contains("ride")
            || words.contains("velo") || words.contains("mtb") || words == "1" || words
            .contains("gravel") {
            return .cycle
        }
        if words.contains("run") || words.contains("jog") {
            return .run
        }
        if words.contains("walk") {
            return .walk
        }
        return .hike
    }

    /// The recording as a leg's track: every point measured, the stored line simplified.
    public var recordedTrack: RecordedTrack? {
        RecordedTrack(points: points, elevations: elevations, start: start, end: end)
    }
}

/// Reads GPX 1.0 and 1.1: each `<trk>` is one track, its segments joined, and each
/// `<rte>` one more. Waypoints on their own are not a way anyone went and are skipped.
public enum GPXReader {
    public enum Failure: Error, Equatable {
        case notGPX
        case noTracks
    }

    public static func read(_ data: Data) throws -> [GPXTrack] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() || !delegate.tracks.isEmpty,
              delegate.sawGPX else { throw Failure.notGPX }
        let tracks = delegate.tracks.filter { $0.points.count >= 2 }
        guard !tracks.isEmpty else { throw Failure.noTracks }
        return tracks
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var tracks: [GPXTrack] = []
        var sawGPX = false

        private var inTrack = false
        private var name: String?
        private var type: String?
        private var points: [Coordinate] = []
        private var elevations: [Double?] = []
        private var times: [Date?] = []
        private var inPoint = false
        private var text = ""
        private let iso = ISO8601DateFormatter()
        private let isoFractional: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        func parser(
            _: XMLParser,
            didStartElement element: String,
            namespaceURI _: String?,
            qualifiedName _: String?,
            attributes: [String: String] = [:]
        ) {
            text = ""
            switch local(element) {
            case "gpx":
                sawGPX = true
            case "trk", "rte":
                inTrack = true
                name = nil
                type = nil
                points = []
                elevations = []
                times = []
            case "trkpt", "rtept":
                guard inTrack,
                      let latitude = attributes["lat"].flatMap(Double.init),
                      let longitude = attributes["lon"].flatMap(Double.init),
                      let point = Coordinate(validating: latitude, longitude) else { return }
                inPoint = true
                points.append(point)
                elevations.append(nil)
                times.append(nil)
            default:
                break
            }
        }

        func parser(_: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(
            _: XMLParser,
            didEndElement element: String,
            namespaceURI _: String?,
            qualifiedName _: String?
        ) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch local(element) {
            case "ele" where inPoint:
                elevations[elevations.count - 1] = Double(value)
            case "time" where inPoint:
                times[times.count - 1] = isoFractional.date(from: value) ?? iso.date(from: value)
            case "trkpt", "rtept":
                inPoint = false
            case "name" where inTrack && !inPoint:
                name = value.isEmpty ? nil : value
            case "type" where inTrack && !inPoint:
                type = value.isEmpty ? nil : value
            case "trk", "rte":
                tracks.append(GPXTrack(
                    name: name,
                    type: type,
                    points: points,
                    elevations: elevations,
                    times: times
                ))
                inTrack = false
            default:
                break
            }
            text = ""
        }

        /// `gpx:trkpt` and `trkpt` alike.
        private func local(_ element: String) -> String {
            element.split(separator: ":").last.map(String.init) ?? element
        }
    }
}
