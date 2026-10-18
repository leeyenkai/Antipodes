import AntipodesCore
import Foundation

/// One closed outline: a country's coastline, or a hole in it.
public struct BorderRing: Sendable {
    public enum Role: UInt8, Sendable {
        case outer = 0
        /// A gap, such as the Lesotho-shaped hole in South Africa.
        case hole = 1
    }

    public let role: Role
    public let box: BoundingBox
    public let coordinates: [Coordinate]
}

/// A country's geometry, keyed the way the user's log refers to countries.
public struct BorderCountry: Sendable {
    /// ISO 3166-1 alpha-2, or `nil` where the source has no code for this land.
    ///
    /// Northern Cyprus, Somaliland and the Siachen Glacier come through unkeyed. They
    /// are drawn, so the coastline is right, but nothing can shade them — which of them
    /// counts as a country is Q-4, and the pipeline does not invent an answer.
    public let countryCode: String?
    public let name: String
    public let continent: Continent?
    public let box: BoundingBox
    public let rings: [BorderRing]
}

/// The bundled country outlines the globe shades and draws (R-GLOBE-2).
///
/// Built by `Tools/placedb/build_borders.py` from Natural Earth, which is public
/// domain. Decoding is pure and takes no dependency on `AntipodesPlaces`: the globe
/// needs every visible polygon on every frame rather than a query, so the geometry
/// lives in its own file rather than in `places.sqlite` (decision D-5).
public struct CountryBorders: Sendable {
    /// Natural Earth's scale denominator in millions: 110 for the whole globe, 50 for
    /// when it is zoomed in far enough for the coarser outline to show.
    public let scale: Int
    public let countries: [BorderCountry]
    /// How many outlines arrived with no ISO code, so the UI can say so rather than
    /// leaving land mysteriously unshaded.
    public let unkeyedCount: Int
    public let pointCount: Int

    public enum DecodingError: Error, Sendable, Equatable {
        case notBorderData
        case unsupportedVersion(Int)
        case truncated
        case malformed(String)
    }

    public static let currentFormatVersion = 1

    /// Countries indexed by ISO code. A code can appear more than once — at 1:50m,
    /// Australia's offshore territories are separate outlines that both resolve to AU —
    /// so this maps to every outline that shares the code.
    public var countriesByCode: [String: [BorderCountry]] {
        var index: [String: [BorderCountry]] = [:]
        for country in countries {
            guard let code = country.countryCode else { continue }
            index[code, default: []].append(country)
        }
        return index
    }

    // MARK: - Decoding

    public init(data: Data) throws {
        var reader = ByteReader(data: data)

        guard try reader.magic() == "ANTB" else { throw DecodingError.notBorderData }
        let version = try Int(reader.uint16())
        guard version == CountryBorders.currentFormatVersion else {
            throw DecodingError.unsupportedVersion(version)
        }
        scale = try Int(reader.uint16())
        let countryCount = try Int(reader.uint32())
        unkeyedCount = try Int(reader.uint32())
        pointCount = try Int(reader.uint32())
        _ = try reader.uint32() // reserved

        var decoded: [BorderCountry] = []
        decoded.reserveCapacity(countryCount)

        for _ in 0 ..< countryCount {
            let keyBytes = try reader.bytes(2)
            let countryCode = try keyBytes == [0, 0] ? nil : reader.text(from: keyBytes)

            let continentRaw = try reader.lengthPrefixedString()
            let continent = continentRaw.isEmpty ? nil : Continent(rawValue: continentRaw)
            if !continentRaw.isEmpty, continent == nil {
                throw DecodingError.malformed("unknown continent \(continentRaw)")
            }

            let name = try reader.lengthPrefixedString()
            let ringCount = try Int(reader.uint16())
            let box = try reader.boundingBox()

            var rings: [BorderRing] = []
            rings.reserveCapacity(ringCount)
            for _ in 0 ..< ringCount {
                let roleRaw = try reader.uint8()
                guard let role = BorderRing.Role(rawValue: roleRaw) else {
                    throw DecodingError.malformed("unknown ring role \(roleRaw)")
                }
                let pointCount = try Int(reader.uint32())
                let ringBox = try reader.boundingBox()
                var coordinates: [Coordinate] = []
                coordinates.reserveCapacity(pointCount)
                for _ in 0 ..< pointCount {
                    try coordinates.append(reader.coordinate())
                }
                rings.append(BorderRing(role: role, box: ringBox, coordinates: coordinates))
            }

            decoded.append(
                BorderCountry(
                    countryCode: countryCode,
                    name: name,
                    continent: continent,
                    box: box,
                    rings: rings
                )
            )
        }

        countries = decoded
    }

    /// Loads a border file, or `nil` when it is not in the bundle.
    ///
    /// Missing borders are a build-configuration problem, not a crash: the globe still
    /// draws pins, arcs and the graticule, and the screen says country shading is
    /// unavailable (see `scripts/fetch-borders.sh`).
    public static func load(from url: URL) throws -> CountryBorders {
        try CountryBorders(data: Data(contentsOf: url, options: .mappedIfSafe))
    }
}

/// A cursor over the border file. Little-endian, unaligned reads, no assumptions about
/// the host's layout.
private struct ByteReader {
    let data: Data
    private var offset = 0

    init(data: Data) {
        self.data = data
    }

    mutating func magic() throws -> String {
        try text(from: bytes(4))
    }

    /// UTF-8 or an error. `String(decoding:as:)` would quietly substitute replacement
    /// characters for corrupt bytes, turning a damaged file into a globe labelled with
    /// nonsense rather than a clear failure.
    func text(from bytes: [UInt8]) throws -> String {
        guard let value = String(bytes: bytes, encoding: .utf8) else {
            throw CountryBorders.DecodingError.malformed("not valid UTF-8")
        }
        return value
    }

    mutating func bytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= data.count else {
            throw CountryBorders.DecodingError.truncated
        }
        defer { offset += count }
        return Array(data[(data.startIndex + offset) ..< (data.startIndex + offset + count)])
    }

    mutating func uint8() throws -> UInt8 {
        try bytes(1)[0]
    }

    mutating func uint16() throws -> UInt16 {
        let raw = try bytes(2)
        return UInt16(raw[0]) | UInt16(raw[1]) << 8
    }

    mutating func uint32() throws -> UInt32 {
        let raw = try bytes(4)
        return UInt32(raw[0]) | UInt32(raw[1]) << 8 | UInt32(raw[2]) << 16 | UInt32(raw[3]) << 24
    }

    mutating func int32() throws -> Int32 {
        try Int32(bitPattern: uint32())
    }

    mutating func lengthPrefixedString() throws -> String {
        let length = try Int(uint8())
        return try text(from: bytes(length))
    }

    /// Micro-degrees back to degrees. The pipeline writes 1e-6 degrees, roughly 11 cm.
    private static let coordinateScale = 1_000_000.0

    mutating func coordinate() throws -> Coordinate {
        let latitude = try Double(int32()) / ByteReader.coordinateScale
        let longitude = try Double(int32()) / ByteReader.coordinateScale
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    mutating func boundingBox() throws -> BoundingBox {
        try BoundingBox(
            minimumLatitude: Double(int32()) / ByteReader.coordinateScale,
            minimumLongitude: Double(int32()) / ByteReader.coordinateScale,
            maximumLatitude: Double(int32()) / ByteReader.coordinateScale,
            maximumLongitude: Double(int32()) / ByteReader.coordinateScale
        )
    }
}
