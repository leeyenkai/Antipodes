import AntipodesCore
import AntipodesGlobe
import Foundation
import Testing

/// The border file is built by a Python script and read by Swift, so the format is a
/// contract between two languages that cannot check each other at compile time. These
/// tests pin the contract down from the Swift side by building the bytes the pipeline
/// would write and decoding them.
///
/// Deliberately hermetic: it builds its own bytes rather than reading the bundled file,
/// so `swift test` stays fast and needs neither the Natural Earth download nor a
/// pipeline run (AGENTS.md §3).
@Suite("Country borders")
struct CountryBordersTests {
    /// Writes the same little-endian layout as `Tools/placedb/build_borders.py`.
    struct Writer {
        var bytes: [UInt8] = []

        mutating func magic(_ text: String = "ANTB") {
            bytes.append(contentsOf: Array(text.utf8))
        }

        mutating func uint16(_ value: UInt16) {
            bytes.append(UInt8(value & 0xFF))
            bytes.append(UInt8(value >> 8 & 0xFF))
        }

        mutating func uint32(_ value: UInt32) {
            for shift in stride(from: 0, to: 32, by: 8) {
                bytes.append(UInt8(value >> UInt32(shift) & 0xFF))
            }
        }

        mutating func int32(_ value: Int32) {
            uint32(UInt32(bitPattern: value))
        }

        mutating func uint8(_ value: UInt8) {
            bytes.append(value)
        }

        mutating func lengthPrefixed(_ text: String) {
            let encoded = Array(text.utf8)
            uint8(UInt8(encoded.count))
            bytes.append(contentsOf: encoded)
        }

        mutating func micro(_ degrees: Double) {
            int32(Int32((degrees * 1_000_000).rounded()))
        }

        /// A square ring, written with its bounding box, as the pipeline does.
        mutating func ring(
            role: UInt8,
            minimumLatitude: Double,
            minimumLongitude: Double,
            maximumLatitude: Double,
            maximumLongitude: Double
        ) {
            let points = [
                (minimumLatitude, minimumLongitude),
                (minimumLatitude, maximumLongitude),
                (maximumLatitude, maximumLongitude),
                (maximumLatitude, minimumLongitude),
            ]
            uint8(role)
            uint32(UInt32(points.count))
            micro(minimumLatitude)
            micro(minimumLongitude)
            micro(maximumLatitude)
            micro(maximumLongitude)
            for (latitude, longitude) in points {
                micro(latitude)
                micro(longitude)
            }
        }

        var data: Data {
            Data(bytes)
        }
    }

    /// Two countries: one keyed with a hole in it, one with no ISO code at all.
    static func sampleFile() -> Data {
        var writer = Writer()
        writer.magic()
        writer.uint16(1) // format version
        writer.uint16(110) // scale
        writer.uint32(2) // countries
        writer.uint32(1) // unkeyed
        writer.uint32(12) // points
        writer.uint32(0) // reserved

        // South Africa, with a Lesotho-shaped hole.
        writer.bytes.append(contentsOf: Array("ZA".utf8))
        writer.lengthPrefixed("africa")
        writer.lengthPrefixed("South Africa")
        writer.uint16(2) // rings
        writer.micro(-35)
        writer.micro(16)
        writer.micro(-22)
        writer.micro(33)
        writer.ring(
            role: 0,
            minimumLatitude: -35,
            minimumLongitude: 16,
            maximumLatitude: -22,
            maximumLongitude: 33
        )
        writer.ring(
            role: 1,
            minimumLatitude: -30.7,
            minimumLongitude: 27,
            maximumLatitude: -28.5,
            maximumLongitude: 29.5
        )

        // Somaliland: drawn, but no ISO code, so nothing can ever shade it.
        writer.uint8(0)
        writer.uint8(0)
        writer.lengthPrefixed("africa")
        writer.lengthPrefixed("Somaliland")
        writer.uint16(1)
        writer.micro(8)
        writer.micro(43)
        writer.micro(11.5)
        writer.micro(49)
        writer.ring(
            role: 0,
            minimumLatitude: 8,
            minimumLongitude: 43,
            maximumLatitude: 11.5,
            maximumLongitude: 49
        )

        return writer.data
    }

    @Test("A border file decodes to its countries, rings and holes")
    func decodesCountries() throws {
        let borders = try CountryBorders(data: Self.sampleFile())

        #expect(borders.scale == 110)
        #expect(borders.countries.count == 2)
        #expect(borders.unkeyedCount == 1)

        let southAfrica = try #require(borders.countries.first { $0.countryCode == "ZA" })
        #expect(southAfrica.name == "South Africa")
        #expect(southAfrica.continent == .africa)
        #expect(southAfrica.rings.count == 2)
        #expect(southAfrica.rings.filter { $0.role == .hole }.count == 1)
        #expect(southAfrica.rings[0].coordinates.count == 4)
    }

    @Test("Coordinates survive the micro-degree round trip")
    func coordinatesAreAccurate() throws {
        let borders = try CountryBorders(data: Self.sampleFile())
        let southAfrica = try #require(borders.countries.first { $0.countryCode == "ZA" })
        let ring = try #require(southAfrica.rings.first)
        let first = try #require(ring.coordinates.first)

        #expect(abs(first.latitude - -35) < 1e-6)
        #expect(abs(first.longitude - 16) < 1e-6)
        #expect(abs(ring.box.minimumLatitude - -35) < 1e-6)
        #expect(abs(ring.box.maximumLongitude - 33) < 1e-6)
    }

    /// Land the source has no ISO code for is still drawn, so the coastline is right,
    /// but it can never be shaded — which of those places counts as a country is Q-4.
    @Test("Land with no ISO code is kept and drawn, but is not in the shading index")
    func unkeyedLandIsDrawnButNotShadeable() throws {
        let borders = try CountryBorders(data: Self.sampleFile())

        let unkeyed = try #require(borders.countries.first { $0.countryCode == nil })
        #expect(unkeyed.name == "Somaliland")
        #expect(!unkeyed.rings.isEmpty)
        #expect(borders.countriesByCode["ZA"]?.count == 1)
        #expect(borders.countriesByCode.count == 1)
    }

    @Test("Something that is not a border file is rejected, not misread")
    func rejectsForeignData() {
        let notBorders = Data("this is a JPEG, honestly".utf8)
        #expect(throws: CountryBorders.DecodingError.notBorderData) {
            _ = try CountryBorders(data: notBorders)
        }
    }

    @Test("A future format version is refused rather than decoded wrongly")
    func rejectsFutureVersion() {
        var writer = Writer()
        writer.magic()
        writer.uint16(99)
        writer.uint16(110)
        writer.uint32(0)
        writer.uint32(0)
        writer.uint32(0)
        writer.uint32(0)

        #expect(throws: CountryBorders.DecodingError.unsupportedVersion(99)) {
            _ = try CountryBorders(data: writer.data)
        }
    }

    @Test("A truncated file is reported, not read off the end")
    func rejectsTruncatedData() {
        let whole = Self.sampleFile()
        let half = whole.prefix(whole.count / 2)

        #expect(throws: CountryBorders.DecodingError.truncated) {
            _ = try CountryBorders(data: Data(half))
        }
        #expect(throws: CountryBorders.DecodingError.truncated) {
            _ = try CountryBorders(data: Data())
        }
    }

    @Test("A header claiming more countries than the file holds is caught")
    func rejectsOverlongCount() {
        var writer = Writer()
        writer.magic()
        writer.uint16(1)
        writer.uint16(110)
        writer.uint32(500) // claims 500 countries
        writer.uint32(0)
        writer.uint32(0)
        writer.uint32(0)

        #expect(throws: CountryBorders.DecodingError.truncated) {
            _ = try CountryBorders(data: writer.data)
        }
    }

    @Test("An empty but well-formed file decodes to no countries")
    func decodesEmptyFile() throws {
        var writer = Writer()
        writer.magic()
        writer.uint16(1)
        writer.uint16(50)
        writer.uint32(0)
        writer.uint32(0)
        writer.uint32(0)
        writer.uint32(0)

        let borders = try CountryBorders(data: writer.data)
        #expect(borders.countries.isEmpty)
        #expect(borders.scale == 50)
        #expect(borders.countriesByCode.isEmpty)
    }
}
