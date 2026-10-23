import Foundation

/// What a human-powered leg was: which network it follows when it has no track of its
/// own (D-36), and how it is described.
public enum HumanActivity: String, CaseIterable, Hashable, Sendable, Codable, Identifiable {
    case hike
    case walk
    case run
    case cycle

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .hike: "Hike"
        case .walk: "Walk"
        case .run: "Run"
        case .cycle: "Bike ride"
        }
    }

    public var symbolName: String {
        switch self {
        case .hike: "figure.hiking"
        case .walk: "figure.walk"
        case .run: "figure.run"
        case .cycle: "figure.outdoor.cycle"
        }
    }

    /// The trails a hike, walk or run follows, or the cycle routes a ride does.
    public var trackKind: TrackKind {
        self == .cycle ? .cycling : .hiking
    }
}

/// The way a leg really went, as the user's own device recorded it — a GPX file or an
/// Apple Health workout route (R-PATH-1, R-PATH-7). The only geometry the log keeps:
/// it is the user's data, not the map's.
public struct RecordedTrack: Hashable, Sendable {
    /// Simplified for storing and drawing; ``lengthKm`` was measured on every point.
    public let points: [Coordinate]
    /// Metres above sea level at each of ``points``, where the recording had them.
    public let elevations: [Double]?
    public let lengthKm: Double
    /// The climb, summed over rises of a few metres or more so GPS noise does not count.
    public let ascentMetres: Double?
    public let highestMetres: Double?
    public let start: Date?
    public let end: Date?

    /// How closely the stored line follows the recording.
    public static let storedToleranceKm = 0.008

    /// A track from every recorded point. Fewer than two usable points is no track.
    public init?(
        points raw: [Coordinate],
        elevations rawElevations: [Double?]? = nil,
        start: Date?,
        end: Date?
    ) {
        guard raw.count >= 2 else { return nil }
        lengthKm = GreatCircle.pathLengthKm(raw)
        let heights = rawElevations.flatMap { values in
            values.count == raw.count && values.allSatisfy { $0 != nil } ? values
                .compactMap(\.self) : nil
        }
        ascentMetres = heights.map(Self.ascent)
        highestMetres = heights?.max()
        let kept = Polyline.simplifiedIndices(raw, toleranceKm: Self.storedToleranceKm)
        points = kept.map { raw[$0] }
        elevations = heights.map { values in kept.map { values[$0] } }
        self.start = start
        self.end = end
    }

    init(
        points: [Coordinate],
        elevations: [Double]?,
        lengthKm: Double,
        ascentMetres: Double?,
        highestMetres: Double?,
        start: Date?,
        end: Date?
    ) {
        self.points = points
        self.elevations = elevations
        self.lengthKm = lengthKm
        self.ascentMetres = ascentMetres
        self.highestMetres = highestMetres
        self.start = start
        self.end = end
    }

    /// Climb counted only once a rise passes a few metres, so a level walk's GPS jitter
    /// adds nothing.
    static func ascent(_ heights: [Double]) -> Double {
        guard var low = heights.first else { return 0 }
        var climbed = 0.0
        var high = low
        for height in heights.dropFirst() {
            if height > high {
                high = height
            } else if high - height > 3 {
                climbed += max(0, high - low)
                low = height
                high = height
            } else if height < low {
                low = height
                high = height
            }
        }
        return climbed + max(0, high - low)
    }

    /// Minutes from the first point to the last, where the recording had times.
    public var minutes: Int? {
        guard let start, let end, end > start else { return nil }
        return Int((end.timeIntervalSince(start) / 60).rounded())
    }
}

extension RecordedTrack: Codable {
    private enum CodingKeys: String, CodingKey {
        case points, elevations, lengthKm, ascentMetres, highestMetres, start, end
    }

    /// Points as base64 of int32 pairs in 1/100,000 of a degree, and heights as int16
    /// metres: a long hike in a few kilobytes of a backup rather than a megabyte of JSON.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var data = Data(capacity: points.count * 8)
        for point in points {
            withUnsafeBytes(of: Int32((point.latitude * 100_000).rounded()).littleEndian) {
                data.append(contentsOf: $0)
            }
            withUnsafeBytes(of: Int32((point.longitude * 100_000).rounded()).littleEndian) {
                data.append(contentsOf: $0)
            }
        }
        try container.encode(data.base64EncodedString(), forKey: .points)
        if let elevations {
            var heights = Data(capacity: elevations.count * 2)
            for height in elevations {
                let metres = Int16(clamping: Int(height.rounded()))
                withUnsafeBytes(of: metres.littleEndian) { heights.append(contentsOf: $0) }
            }
            try container.encode(heights.base64EncodedString(), forKey: .elevations)
        }
        try container.encode(lengthKm, forKey: .lengthKm)
        try container.encodeIfPresent(ascentMetres, forKey: .ascentMetres)
        try container.encodeIfPresent(highestMetres, forKey: .highestMetres)
        try container.encodeIfPresent(start, forKey: .start)
        try container.encodeIfPresent(end, forKey: .end)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let data = try Data(base64Encoded: container.decode(String.self, forKey: .points)),
              data.count >= 16, data.count.isMultiple(of: 8) else {
            throw DecodingError.dataCorruptedError(
                forKey: .points,
                in: container,
                debugDescription: "A recorded track needs at least two points"
            )
        }
        var points: [Coordinate] = []
        points.reserveCapacity(data.count / 8)
        try data.withUnsafeBytes { raw in
            for offset in stride(from: 0, to: data.count, by: 8) {
                let latitude = Double(Int32(littleEndian: raw.loadUnaligned(
                    fromByteOffset: offset,
                    as: Int32.self
                )))
                let longitude = Double(Int32(littleEndian: raw.loadUnaligned(
                    fromByteOffset: offset + 4,
                    as: Int32.self
                )))
                guard let point = Coordinate(validating: latitude / 100_000, longitude / 100_000)
                else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .points,
                        in: container,
                        debugDescription: "A point is off the Earth"
                    )
                }
                points.append(point)
            }
        }
        var elevations: [Double]?
        if let text = try container.decodeIfPresent(String.self, forKey: .elevations),
           let heights = Data(base64Encoded: text), heights.count == points.count * 2 {
            elevations = heights.withUnsafeBytes { raw in
                stride(from: 0, to: heights.count, by: 2).map {
                    Double(Int16(littleEndian: raw.loadUnaligned(
                        fromByteOffset: $0,
                        as: Int16.self
                    )))
                }
            }
        }
        let length = try container.decode(Double.self, forKey: .lengthKm)
        try self.init(
            points: points,
            elevations: elevations,
            lengthKm: JourneyLeg.plausibleDistance(length) ?? GreatCircle.pathLengthKm(points),
            ascentMetres: container.decodeIfPresent(Double.self, forKey: .ascentMetres),
            highestMetres: container.decodeIfPresent(Double.self, forKey: .highestMetres),
            start: container.decodeIfPresent(Date.self, forKey: .start),
            end: container.decodeIfPresent(Date.self, forKey: .end)
        )
    }
}
