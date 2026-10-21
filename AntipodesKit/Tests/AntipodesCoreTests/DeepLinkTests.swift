import AntipodesCore
import Foundation
import Testing

@Suite("Deep links")
struct DeepLinkTests {
    @Test("Every link survives a round trip through its URL")
    func roundTrip() {
        let id = UUID()
        let links: [DeepLink] = [
            .globe, .trips, .stats, .collections, .log,
            .collection("nordic-capitals"), .trip(id), .visit(id), .journey(id),
        ]
        for link in links {
            #expect(DeepLink(url: link.url) == link, "\(link)")
        }
        #expect(DeepLink.visit(id).url.absoluteString == "antipodes://visit/\(id.uuidString)")
        #expect(DeepLink.globe.url.absoluteString == "antipodes://globe")
    }

    @Test("Anything that is not one of ours is refused")
    func refusals() throws {
        for text in [
            "https://globe", "antipodes://nowhere", "antipodes://visit/not-a-uuid",
            "antipodes://visit", "antipodes://collection/", "antipodes://globe/extra",
        ] {
            let url = try #require(URL(string: text))
            #expect(DeepLink(url: url) == nil, "\(text)")
        }
    }
}
