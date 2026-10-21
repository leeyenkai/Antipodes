import AntipodesCore
import AntipodesPlaces
import AntipodesStats
import SwiftUI

/// A headline number with its caveat underneath.
///
/// The caveat is part of the card, not a tooltip, because a stat that quietly dropped
/// records is the failure mode this app is trying to avoid (R-CALC-5).
struct StatCard: View {
    let title: String
    let value: String
    var detail: String?
    var caveat: String?
    var symbol: String?
    var tint: Color = .accentColor
    /// What the card says when shared, where that should read differently from the
    /// dashboard ("countries visited" rather than "Countries").
    var shareTitle: String?
    @Environment(\.shareStat) private var shareStat

    init(
        title: String,
        value: String,
        detail: String? = nil,
        caveat: String? = nil,
        symbol: String? = nil,
        tint: Color = .accentColor,
        shareTitle: String? = nil
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.caveat = caveat
        self.symbol = symbol
        self.tint = tint
        self.shareTitle = shareTitle
    }

    init(headline: TravelStatistics.Headline) {
        self.init(
            title: headline.title,
            value: headline.value,
            detail: headline.detail,
            caveat: headline.caveat
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            Text(value)
                .font(.statValue(28))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let caveat {
                CaveatLabel(text: caveat)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .card(padding: 14)
        .accessibilityElement(children: .combine)
        .contextMenu {
            if let shareStat {
                Button("Share…", systemImage: "square.and.arrow.up") {
                    shareStat(.stat(
                        title: shareTitle ?? title.lowercased(),
                        value: value,
                        detail: detail,
                        symbol: symbol ?? "chart.bar.fill"
                    ))
                }
            }
        }
    }
}

struct CaveatLabel: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A search result, as the add sheet and every place picker list it.
struct PlaceResultRow: View {
    let result: PlaceSearchResult

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(systemName: result.kind.symbolName, tint: result.kind.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .foregroundStyle(.primary)
                if let subtitle = result.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let code = result.code, result.kind == .airport || result.kind == .country {
                Text(code)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: .capsule)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(result.kind.displayName)
    }
}

/// A place the user has logged.
struct PlaceRow: View {
    let place: PlaceReference
    var subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(systemName: place.kind.symbolName, tint: place.kind.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                Text(subtitle ?? place.contextLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension PlaceReference {
    /// "Rome, Italy" for a landmark, "Norway" for a city, the kind for a country.
    var contextLine: String {
        let parts: [String?] =
            switch kind {
            case .country: [continent?.displayName]
            case .region, .city: [regionName, countryName]
            case .landmark, .airport: [cityName, countryName]
            case .route: ["Route"]
            case .custom: [regionName, countryName ?? "Custom pin"]
            }
        let text = parts.compactMap(\.self).filter { !$0.isEmpty && $0 != name }
            .joined(separator: ", ")
        return text.isEmpty ? kind.displayName : text
    }

    var flag: String {
        Format.flag(countryCode)
    }
}

struct VisitRow: View {
    let visit: Visit

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(systemName: visit.place.kind.symbolName, tint: visit.place.kind.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(visit.place.name)
                    if let rating = visit.rating {
                        Text(String(repeating: "★", count: rating))
                            .font(.caption2)
                            .foregroundStyle(Palette.pin)
                            .accessibilityLabel("\(rating) stars")
                    }
                }
                Text("\(visit.visitType.displayName) · \(visit.date.displayText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(visit.place.flag)
                .font(.title3)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct JourneyRow: View {
    @Environment(AppModel.self) private var model
    let journey: Journey

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(
                systemName: journey.legs.first?.mode.symbolName ?? "arrow.right",
                tint: Palette.mode(journey.legs.first?.mode ?? .flight)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(journey.displayTitle)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [
            Format.distance(
                journey.totalDistanceKm,
                model.rules.unitSystem,
                approximate: journey.legs.contains { $0.distanceSource.isApproximate }
            ),
        ]
        if journey.legs.count > 1 {
            parts.append("\(journey.legs.count) legs")
        }
        parts.append(journey.date.displayText)
        return parts.joined(separator: " · ")
    }
}

extension Journey {
    /// "OSL → JFK", "Oslo → Bergen → Flåm", or the user's own title.
    var displayTitle: String {
        if let title, !title.isEmpty {
            return title
        }
        guard let first = legs.first else { return "Journey" }
        var stops = [first.origin.shortName]
        for leg in legs {
            if leg.origin.id != legs.first?.origin.id, stops.last != leg.origin.shortName {
                stops.append(leg.origin.shortName)
            }
            stops.append(leg.destination.shortName)
        }
        if stops.count > 4 {
            stops = [stops[0], "…", stops[stops.count - 1]]
        }
        return stops.joined(separator: " → ")
    }
}

/// One to five stars, or none.
struct RatingPicker: View {
    @Binding var rating: Int?

    var body: some View {
        LabeledContent("Rating") {
            HStack(spacing: 6) {
                ForEach(1 ... 5, id: \.self) { star in
                    Button {
                        rating = rating == star ? nil : star
                    } label: {
                        Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                            .foregroundStyle(star <= (rating ?? 0) ? Palette.pin : .secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(rating.map { "\($0) stars" } ?? "No rating")
    }
}

/// Assigning a trip is optional — a visit can stand alone and be filed later
/// (R-MODEL-3).
struct TripPicker: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: UUID?
    @State private var isCreating = false
    @State private var newTripName = ""

    var body: some View {
        Picker("Trip", selection: $selection) {
            Text("None").tag(UUID?.none)
            ForEach(model.tripsNewestFirst) { trip in
                Text(trip.displayName(model: model)).tag(UUID?.some(trip.id))
            }
        }
        Button("New Trip…", systemImage: "plus") { isCreating = true }
            .alert("New Trip", isPresented: $isCreating) {
                TextField("Name", text: $newTripName)
                Button("Cancel", role: .cancel) { newTripName = "" }
                Button("Create") {
                    do {
                        selection = try model.createTrip(name: newTripName).id
                    } catch {
                        model.errorMessage = AppModel.tripNotCreated(error)
                    }
                    newTripName = ""
                }
            } message: {
                Text("Give the trip a name, such as \"Japan 2025\".")
            }
    }
}

extension Trip {
    /// The trip's name, or its dates and first place when it has none.
    @MainActor
    func displayName(model: AppModel) -> String {
        if let name, !name.isEmpty {
            return name
        }
        if let dates = model.dates(ofTrip: id) {
            let place = model.log.visits(inTrip: id).first?.place.name
            return [place, dates.text].compactMap(\.self).joined(separator: ", ")
        }
        return "Untitled trip"
    }
}

/// A full-width empty state with an action, used wherever a list has nothing yet.
struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glassProminent)
            }
        }
    }
}

/// A labelled value that wraps rather than truncates, for detail screens.
struct DetailRow: View {
    let title: String
    let value: String
    var systemImage: String?

    var body: some View {
        LabeledContent {
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        } label: {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
    }
}
