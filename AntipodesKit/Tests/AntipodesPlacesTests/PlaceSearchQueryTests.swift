import AntipodesCore
@testable import AntipodesPlaces
import Foundation
import Testing

@Suite("FTS5 query building")
struct PlaceSearchQueryTests {
    /// The last token gets a prefix wildcard, which is what makes search feel live as
    /// the user types (R-LOG-1).
    @Test("A single token becomes a quoted prefix term")
    func singleToken() {
        #expect(PlaceSearchQuery.matchExpression(for: "oslo") == "\"oslo\"*")
    }

    @Test("Earlier tokens are exact; only the last is a prefix")
    func multipleTokens() {
        #expect(PlaceSearchQuery.matchExpression(for: "new york") == "\"new\" \"york\"*")
        #expect(
            PlaceSearchQuery.matchExpression(for: "rio de jan")
                == "\"rio\" \"de\" \"jan\"*"
        )
    }

    /// FTS5 treats these as syntax. Unescaped, a user typing a quote or a hyphen gets
    /// a SQL error instead of results.
    @Test("FTS5 operators in user input are stripped, not interpreted")
    func operatorsAreNeutralised() {
        #expect(PlaceSearchQuery.matchExpression(for: "oslo*") == "\"oslo\"*")
        #expect(PlaceSearchQuery.matchExpression(for: "\"oslo\"") == "\"oslo\"*")
        #expect(PlaceSearchQuery.matchExpression(for: "oslo OR bergen")
            == "\"oslo\" \"or\" \"bergen\"*")
        #expect(PlaceSearchQuery.matchExpression(for: "st. moritz")
            == "\"st\" \"moritz\"*")
        #expect(PlaceSearchQuery.matchExpression(for: "x NEAR/2 y")
            == "\"x\" \"near\" \"2\" \"y\"*")
        #expect(PlaceSearchQuery.matchExpression(for: "a^b") == "\"a\" \"b\"*")
    }

    @Test("A query with nothing searchable in it returns nil rather than bad SQL")
    func emptyQueries() {
        #expect(PlaceSearchQuery.matchExpression(for: "") == nil)
        #expect(PlaceSearchQuery.matchExpression(for: "   ") == nil)
        #expect(PlaceSearchQuery.matchExpression(for: "***") == nil)
        #expect(PlaceSearchQuery.matchExpression(for: "-") == nil)
    }

    @Test("Accented input is preserved; the index holds the folded copy")
    func accentedInput() {
        #expect(PlaceSearchQuery.matchExpression(for: "Tromsø") == "\"tromsø\"*")
        #expect(PlaceSearchQuery.matchExpression(for: "São Paulo")
            == "\"são\" \"paulo\"*")
    }
}
