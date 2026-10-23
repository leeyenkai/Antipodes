#if canImport(HealthKit) && os(iOS)
    import AntipodesCore
    import CoreLocation
    import Foundation
    import HealthKit

    /// Hikes, walks, runs and rides Apple Health recorded with a route, read on the
    /// device and only when the user asks (R-PATH-1, D-36). Antipodes reads workouts and
    /// their routes and writes nothing to Health.
    @MainActor
    final class HealthWorkouts {
        struct Workout: Identifiable {
            let id: UUID
            let activity: HumanActivity
            let start: Date
        }

        private let store = HKHealthStore()
        private var found: [UUID: HKWorkout] = [:]

        static var isAvailable: Bool {
            HKHealthStore.isHealthDataAvailable()
        }

        private static let activities: [HKWorkoutActivityType: HumanActivity] = [
            .hiking: .hike,
            .walking: .walk,
            .running: .run,
            .cycling: .cycle,
        ]

        /// Every such workout that has a route, newest first.
        func workouts() async throws -> [Workout] {
            try await store.requestAuthorization(
                toShare: [],
                read: [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
            )
            let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: Self.activities.keys
                .map {
                    HKQuery.predicateForWorkouts(with: $0)
                })
            let query = HKSampleQueryDescriptor(
                predicates: [.workout(predicate)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
                limit: 500
            )
            let workouts = try await query.result(for: store)
            var result: [Workout] = []
            for workout in workouts {
                guard let activity = Self.activities[workout.workoutActivityType],
                      try await !routes(of: workout).isEmpty else { continue }
                found[workout.uuid] = workout
                result.append(Workout(
                    id: workout.uuid,
                    activity: activity,
                    start: workout.startDate
                ))
            }
            return result
        }

        /// The route Health recorded for a workout, as a leg's track.
        func track(for id: UUID) async throws -> RecordedTrack? {
            guard let workout = found[id] else { return nil }
            var points: [Coordinate] = []
            var heights: [Double?] = []
            for route in try await routes(of: workout) {
                for try await location in HKWorkoutRouteQueryDescriptor(route).results(for: store) {
                    guard let point = Coordinate(
                        validating: location.coordinate.latitude,
                        location.coordinate.longitude
                    ) else { continue }
                    points.append(point)
                    heights.append(location.verticalAccuracy >= 0 ? location.altitude : nil)
                }
            }
            return RecordedTrack(
                points: points,
                elevations: heights,
                start: workout.startDate,
                end: workout.endDate
            )
        }

        private func routes(of workout: HKWorkout) async throws -> [HKWorkoutRoute] {
            let query = HKSampleQueryDescriptor(
                predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))],
                sortDescriptors: []
            )
            return try await query.result(for: store)
        }
    }
#endif
