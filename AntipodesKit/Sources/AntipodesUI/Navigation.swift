import AntipodesCore
import SwiftUI

/// Every screen a record can be opened on, so any list in any tab can link to a trip,
/// a visit, a journey, a country or a collection and the destination is the same.
enum LogRoute: Hashable {
    case trip(UUID)
    case visit(UUID)
    case journey(UUID)
    case country(String)
    case collection(String)
    case allVisits
}

struct LogDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: LogRoute.self) { route in
            switch route {
            case let .trip(id): TripDetailView(tripID: id)
            case let .visit(id): VisitDetailView(visitID: id)
            case let .journey(id): JourneyDetailView(journeyID: id)
            case let .country(code): CountryDetailView(countryCode: code)
            case let .collection(id): CollectionDetailView(collectionID: id)
            case .allVisits: AllRecordsView()
            }
        }
    }
}

extension View {
    func logDestinations() -> some View {
        modifier(LogDestinations())
    }
}

/// A visit opened from anywhere: the same form that logged it, editing in place.
struct VisitDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let visitID: UUID

    var body: some View {
        if let visit = model.log.visits.first(where: { $0.id == visitID }) {
            VisitForm(place: visit.place, existing: visit) { dismiss() }
        } else {
            ContentUnavailableView("Visit deleted", systemImage: "trash")
        }
    }
}

/// A journey opened from anywhere: its summary, then its legs, editable in place.
struct JourneyDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let journeyID: UUID

    var body: some View {
        if let journey = model.log.journeys.first(where: { $0.id == journeyID }) {
            JourneyEditor(existing: journey) { dismiss() }
                .safeAreaInset(edge: .top, spacing: 0) {
                    EmptyView()
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(
                            item: ShareCardImage(card: .journey(journey), model: model),
                            preview: SharePreview(
                                journey.displayTitle,
                                image: Image(systemName: "airplane")
                            )
                        )
                    }
                }
        } else {
            ContentUnavailableView("Journey deleted", systemImage: "trash")
        }
    }
}
