import AntipodesCore
import Foundation

/// A photo's when and where, as read on the device. Nothing else about the photo is
/// read, and nothing is uploaded (R-LOG-7, R-PRIV-4).
public struct PhotoSample: Hashable, Sendable {
    public let taken: Date
    public let coordinate: Coordinate

    public init(taken: Date, coordinate: Coordinate) {
        self.taken = taken
        self.coordinate = coordinate
    }
}

/// A photo with the bundled place it was taken nearest to.
public struct LocatedPhoto: Hashable, Sendable {
    public let sample: PhotoSample
    public let place: PlaceReference

    public init(sample: PhotoSample, place: PlaceReference) {
        self.sample = sample
        self.place = place
    }
}

/// A visit the photos suggest, for the user to confirm or skip.
public struct VisitSuggestion: Hashable, Sendable, Identifiable {
    public let id: String
    public let place: PlaceReference
    public let start: CalendarDate
    public let end: CalendarDate
    public let photoCount: Int
    /// A visit to the same place on overlapping days is already in the log.
    public let alreadyLogged: Bool

    /// One day, or the span the photos cover.
    public var date: FlexibleDate {
        start == end ? .day(start) : .span(start, end)
    }

    /// Stayed if the photos span more than one day, otherwise a day trip.
    public var suggestedType: VisitType {
        start == end ? .dayTrip : .stayed
    }
}

/// Turns a photo library's locations into suggested visits (R-LOG-7).
///
/// Photos are taken in order; consecutive photos at the same place with no more than
/// `maximumGapDays` between them become one stay. The home city, where most photos are
/// taken, is left out — nobody wants to log the kitchen. Each suggestion records how many
/// photos support it, so the review screen can show its evidence.
public enum PhotoClustering {
    /// Photos of one place this many days apart or less are one stay. Three tolerates a
    /// day without photos in the middle of a trip without merging two trips a week apart.
    public static let maximumGapDays = 3

    public static func suggest(
        _ photos: [LocatedPhoto],
        home: PlaceReference? = nil,
        existing: [Visit] = [],
        deviceTimeZone: TimeZone = .current
    ) -> [VisitSuggestion] {
        struct Stay {
            var place: PlaceReference
            var start: CalendarDate
            var end: CalendarDate
            var count: Int
        }

        let away = photos.filter { photo in
            guard let home else { return true }
            return !(photo.place.covers(home) || home.covers(photo.place))
        }
        let ordered = away.sorted { ($0.sample.taken, $0.place.id.description) < (
            $1.sample.taken,
            $1.place.id.description
        ) }

        var stays: [Stay] = []
        var open: [PlaceID: Int] = [:]
        for photo in ordered {
            // The day the photo was taken, on the clock where it was taken where the
            // place's zone is known, so a photo at 23:30 in Tokyo is not filed under the
            // next day because the phone is set to Oslo time now.
            let zone = photo.place.timeZone ?? deviceTimeZone
            guard let day = CalendarDate(photo.sample.taken, in: zone) else { continue }
            if let index = open[photo.place.id], stays[index].end.days(to: day) <= maximumGapDays {
                stays[index].end = max(stays[index].end, day)
                stays[index].count += 1
            } else {
                stays.append(Stay(place: photo.place, start: day, end: day, count: 1))
                open[photo.place.id] = stays.count - 1
            }
        }

        return stays.map { stay in
            let logged = existing.contains { visit in
                guard visit.place.id == stay.place.id,
                      let first = visit.date.earliestDay,
                      let last = visit.date.latestDay
                else { return false }
                return first <= stay.end && last >= stay.start
            }
            return VisitSuggestion(
                id: "\(stay.place.id.description)@\(stay.start.iso)",
                place: stay.place,
                start: stay.start,
                end: stay.end,
                photoCount: stay.count,
                alreadyLogged: logged
            )
        }
        .sorted { ($0.start, $0.place.name) > ($1.start, $1.place.name) }
    }
}
